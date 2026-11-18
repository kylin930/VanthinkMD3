-- 统一 HTTP Service 层
-- 职责：URL/查询参数编码、鉴权头注入、JSON 解析、业务错误码映射、
-- 网络异常分类、异步执行（xTask io 调度器，回调回到主线程）。
-- 所有耗时请求都在后台线程执行，主线程只做 UI 更新。

local logger = require "app.utils.logger"

local M = {}

local URLEncoder = luajava.bindClass("java.net.URLEncoder")
local NetworkOnMainThread = luajava.bindClass("android.os.NetworkOnMainThreadException")

local tokenProvider = function() return nil end
local authInvalidHandler = nil

function M.setTokenProvider(provider)
  tokenProvider = provider
end

function M.setAuthInvalidHandler(handler)
  authInvalidHandler = handler
end

-- 认证失效的兜底处理只执行一次，避免多个请求同时失败时反复提示
local authHandled = false

function M.resetAuthHandled()
  authHandled = false
end

local function urlEncode(value)
  local ok, result = pcall(function()
    return tostring(URLEncoder.encode(tostring(value), "UTF-8"))
  end)
  if ok then return result end
  return tostring(value)
end

local function buildUrl(url, query)
  if type(query) ~= "table" then return url end
  local parts = {}
  for _, item in ipairs(query) do
    local key = item[1]
    local value = item[2]
    if key ~= nil and value ~= nil and tostring(value) ~= "" then
      parts[#parts + 1] = urlEncode(key) .. "=" .. urlEncode(value)
    end
  end
  if #parts == 0 then return url end
  local separator = "?"
  if string.find(url, "?", 1, true) ~= nil then separator = "&" end
  return url .. separator .. table.concat(parts, "&")
end

-- 把任意 Lua 值安全转成字符串，用于表单字段
local function formValue(value)
  if type(value) == "number" then
    if math.floor(value) == value then
      return tostring(math.floor(value))
    end
    return tostring(value)
  end
  if type(value) == "boolean" then
    return value and "1" or "0"
  end
  return tostring(value)
end

local function normalizeForm(form)
  if type(form) ~= "table" then return nil end
  local out = {}
  for key, value in pairs(form) do
    if value ~= nil then
      out[tostring(key)] = formValue(value)
    end
  end
  return out
end

-- 将底层异常归类
local function classifyError(message)
  local text = tostring(message or "")
  if string.find(text, "UnknownHost", 1, true) ~= nil
    or string.find(text, "Unable to resolve host", 1, true) ~= nil then
    return "dns", "无法解析服务器地址，请检查网络"
  end
  if string.find(text, "SocketTimeout", 1, true) ~= nil
    or string.find(text, "timeout", 1, true) ~= nil then
    return "timeout", "请求超时，请稍后重试"
  end
  if string.find(text, "SSL", 1, true) ~= nil
    or string.find(text, "CertPathValidator", 1, true) ~= nil then
    return "tls", "安全连接失败，请检查系统时间或网络环境"
  end
  if string.find(text, "ConnectException", 1, true) ~= nil
    or string.find(text, "Connect", 1, true) ~= nil then
    return "connect", "网络连接失败，请检查网络后重试"
  end
  return "unknown", "网络请求失败：" .. text
end

-- 执行请求（后台线程）
local function execute(opts)
  local headers = {}
  if opts.auth then
    local token = tokenProvider()
    if token ~= nil and token ~= "" then
      headers["Authorization"] = token
    end
  end
  if type(opts.headers) == "table" then
    for key, value in pairs(opts.headers) do
      headers[tostring(key)] = tostring(value)
    end
  end

  local url = buildUrl(opts.url, opts.query)
  local method = opts.method or "GET"
  local ok, response = pcall(function()
    if method == "POST" then
      if opts.json ~= nil then
        return okhttp.postJson(url, json.encode(opts.json), headers)
      end
      return okhttp.post(url, normalizeForm(opts.form) or {}, headers)
    end
    return okhttp.get(url, headers)
  end)

  if not ok then
    local kind, message = classifyError(response)
    logger.w("HTTP 失败 " .. tostring(opts.tag or url) .. " -> " .. tostring(response))
    return {
      ok = false,
      kind = kind,
      message = message,
      rawError = tostring(response),
    }
  end

  local code = 0
  pcall(function() code = response.code() end)
  local body = ""
  pcall(function() body = response.body().string() end)

  if code < 200 or code >= 300 then
    logger.w("HTTP 状态异常 " .. tostring(opts.tag or url) .. " -> " .. tostring(code))
    return {
      ok = false,
      kind = "http",
      httpCode = code,
      message = "服务器返回状态码 " .. tostring(code),
    }
  end

  local parsed = nil
  if body ~= nil and body ~= "" then
    local decodeOk, decoded = pcall(function() return json.decode(body) end)
    if decodeOk then
      parsed = decoded
    end
  end

  local result = {
    ok = true,
    httpCode = code,
    raw = body,
  }

  if type(parsed) == "table" then
    result.body = parsed
    result.data = parsed.data
    result.errcode = tonumber(parsed.errcode) or 0
    result.errstr = parsed.errstr
    if result.errcode ~= 0 then
      result.ok = false
      result.kind = (result.errcode == 44) and "auth" or "api"
      result.message = parsed.errstr or ("服务返回错误码 " .. tostring(result.errcode))
    end
  elseif parsed == nil and body ~= "" then
    result.body = nil
    result.data = nil
  end

  return result
end

-- 发起异步请求。callback(result) 在主线程执行。
function M.request(opts, callback)
  -- 需要鉴权但没有 Token 时直接返回本地错误，避免发出必然失败的请求
  if opts.auth then
    local token = tokenProvider()
    if token == nil or token == "" then
      local localResult = {
        ok = false,
        kind = "auth",
        message = "尚未登录，请先登录",
      }
      if callback ~= nil then
        pcall(callback, localResult)
      end
      return nil
    end
  end

  local job = nil
  local tag = opts.tag or opts.url
  job = xTask {
    dispatcher = "io",
    task = function()
      local ok, result = pcall(execute, opts)
      if not ok then
        logger.e("HTTP 执行异常 " .. tostring(tag) .. ": " .. tostring(result))
        return {
          ok = false,
          kind = "unknown",
          message = "请求处理失败，请稍后重试",
          rawError = tostring(result),
        }
      end
      return result
    end,
    callback = function(result)
      if type(result) ~= "table" then
        result = { ok = false, kind = "unknown", message = "响应格式异常" }
      end
      if result.kind == "auth" and authInvalidHandler ~= nil and not authHandled then
        authHandled = true
        pcall(authInvalidHandler)
      end
      logger.d("HTTP " .. tostring(tag) .. " ok=" .. tostring(result.ok)
        .. " kind=" .. tostring(result.kind) .. " errcode=" .. tostring(result.errcode))
      if callback ~= nil then
        local callOk, err = pcall(callback, result)
        if not callOk then
          logger.e("HTTP 回调异常 " .. tostring(tag) .. ": " .. tostring(err))
        end
      end
    end,
  }
  return job
end

function M.cancel(job)
  if job == nil then return end
  pcall(function() job.cancel() end)
end

return M
