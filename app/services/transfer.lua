-- Auth 迁移 / 二维码授权服务
-- 原项目协议（依据 trans.js、qr.js 与线上响应确认）：
--   生成端：GET https://zxzjurl.930390.xyz/create?auth=<token>
--           -> { id, url }；二维码内容就是返回的 url
--   生成端轮询：GET https://zxzjurl.930390.xyz/status/<code>（code = url 最后一段）
--           -> data.used = true 表示已被扫描领取
--   接收端：GET <url> -> { auth: <token> }
-- 注意：该服务为非官方第三方中转，属于可选能力；token 通过查询参数发送，
-- 本应用在界面上明确提示风险，且只在用户主动操作时调用。

local config = require "app.config"
local http = require "app.services.http"
local state = require "app.state"

local M = {}

function M.create(callback)
  if not state.isLoggedIn() then
    callback(false, "请先登录后再生成迁移二维码")
    return nil
  end
  return http.request({
    url = config.THIRD_PARTY.authTransferCreate,
    method = "GET",
    query = { { "auth", state.token } },
    auth = false,
    tag = "transfer/create",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "生成二维码失败")
      return
    end
    local body = result.body or {}
    local url = body.url
    if url == nil or tostring(url) == "" then
      callback(false, "生成二维码失败：服务未返回有效地址")
      return
    end
    callback(true, {
      id = body.id,
      url = tostring(url),
      code = M.codeFromUrl(tostring(url)),
    })
  end)
end

function M.codeFromUrl(url)
  local text = tostring(url or "")
  local code = string.match(text, "([^/]+)$")
  if code == nil then return "" end
  return code
end

-- 查询二维码是否已被领取
function M.checkStatus(code, callback)
  if code == nil or code == "" then
    callback(false, "二维码状态未知")
    return nil
  end
  return http.request({
    url = config.THIRD_PARTY.authTransferStatus .. code,
    method = "GET",
    auth = false,
    tag = "transfer/status",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "状态查询失败", result)
      return
    end
    local body = result.body or {}
    local used = false
    if type(body.data) == "table" and body.data.used ~= nil then
      used = body.data.used == true or body.data.used == 1 or body.data.used == "1"
    elseif body.used ~= nil then
      used = body.used == true or body.used == 1 or body.used == "1"
    end
    callback(true, { used = used })
  end)
end

-- 接收端：用二维码里的 url 换取 token（手动输入或外部扫码后粘贴）
function M.receive(url, callback)
  local target = tostring(url or "")
  if target == "" then
    callback(false, "请输入二维码内容或链接")
    return nil
  end
  if string.sub(target, 1, 8) ~= "https://" then
    callback(false, "链接格式不正确，需以 https:// 开头")
    return nil
  end
  return http.request({
    url = target,
    method = "GET",
    auth = false,
    tag = "transfer/receive",
  }, function(result)
    if not result.ok then
      if result.httpCode == 410 then
        callback(false, "该二维码已被使用（一次性有效）")
        return
      end
      if result.httpCode == 404 then
        callback(false, "该二维码不存在或已过期")
        return
      end
      callback(false, result.message or "领取失败，链接可能已失效")
      return
    end
    local body = result.body or {}
    local token = body.auth or (type(body.data) == "table" and body.data.auth) or nil
    if token == nil or tostring(token) == "" then
      callback(false, "该链接无效或已被使用")
      return
    end
    callback(true, tostring(token))
  end)
end

return M
