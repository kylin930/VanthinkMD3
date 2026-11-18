-- 账号服务：登录、账号信息、退出登录。
-- 登录接口与字段依据实际响应验证：
--   POST /api/auth/student/login  { phone, password } -> { data: { token } }
--   errcode 108 = 手机号未注册

local config = require "app.config"
local http = require "app.services.http"
local state = require "app.state"
local logger = require "app.utils.logger"

local M = {}

local function parseLoginError(result)
  local errcode = tonumber(result.errcode)
  if errcode == config.ERRCODE.PHONE_NOT_REGISTERED then
    return "该手机号未注册，请先在助教端注册"
  end
  if result.kind == "auth" then
    return "账号或密码不正确"
  end
  if result.kind == "api" then
    return result.errstr or "登录失败，请稍后重试"
  end
  return result.message or "登录失败，请稍后重试"
end

-- 登录：成功回调 (true)，失败回调 (false, 可读错误信息)
function M.login(phone, password, callback)
  return http.request({
    url = config.API.login,
    method = "POST",
    form = { phone = phone, password = password },
    auth = false,
    tag = "auth/login",
  }, function(result)
    if not result.ok then
      logger.w("登录失败: " .. tostring(result.message))
      callback(false, parseLoginError(result))
      return
    end
    local data = result.data
    local token = nil
    if type(data) == "table" then
      token = data.token or data.auth
    end
    if token == nil or tostring(token) == "" then
      callback(false, "账号或密码不正确")
      return
    end
    state.setToken(tostring(token))
    callback(true)
  end)
end

-- 拉取当前账号信息
function M.fetchAccount(callback)
  return http.request({
    url = config.API.account,
    method = "GET",
    auth = true,
    tag = "auth/account",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "账号信息加载失败", result)
      return
    end
    local data = result.data
    if type(data) ~= "table" then
      callback(false, "账号信息格式异常", result)
      return
    end
    state.setAccount(data)
    callback(true, data)
  end)
end

function M.logout()
  state.reset()
end

return M
