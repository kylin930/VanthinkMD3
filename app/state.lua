-- 全局运行状态：登录态、当前账号、通知未读数。
-- Token 只保存在安全存储中，内存里保留一份用于请求注入；
-- 账号展示信息（昵称/头像）为非敏感数据，可缓存在偏好设置里。

local secure = require "app.storage.secure"
local pref = require "app.storage.preferences"
local logger = require "app.utils.logger"

local M = {}

M.account = nil
M.token = nil
M.unreadCount = 0

local listeners = {}

local function notify(event)
  for _, fn in ipairs(listeners) do
    local ok, err = pcall(fn, event, M)
    if not ok then
      logger.e("state 监听异常: " .. tostring(err))
    end
  end
end

function M.subscribe(fn)
  listeners[#listeners + 1] = fn
  return function()
    for index, item in ipairs(listeners) do
      if item == fn then
        table.remove(listeners, index)
        break
      end
    end
  end
end

function M.loadToken()
  M.token = secure.getSecret("auth_token")
  return M.token
end

function M.setToken(token)
  local text = tostring(token or "")
  if text == "" then
    M.clearToken()
    return false
  end
  M.token = text
  local ok = secure.setSecret("auth_token", text)
  if not ok then
    logger.e("Token 安全存储失败")
  end
  notify("token")
  return ok
end

function M.clearToken()
  M.token = nil
  secure.removeSecret("auth_token")
  notify("token")
end

function M.isLoggedIn()
  return M.token ~= nil and M.token ~= ""
end

local ACCOUNT_KEY = "account_cache"

function M.loadAccountCache()
  local raw = pref.getString(ACCOUNT_KEY, nil)
  if raw == nil then return nil end
  local ok, decoded = pcall(function() return json.decode(raw) end)
  if not ok or type(decoded) ~= "table" then return nil end
  M.account = decoded
  return decoded
end

function M.setAccount(account)
  M.account = account
  if type(account) == "table" then
    pcall(function() pref.setString(ACCOUNT_KEY, json.encode(account)) end)
  end
  notify("account")
end

function M.clearAccount()
  M.account = nil
  pref.remove(ACCOUNT_KEY)
  notify("account")
end

function M.setUnreadCount(count)
  local value = tonumber(count) or 0
  if value < 0 then value = 0 end
  local changed = value ~= M.unreadCount
  M.unreadCount = value
  if changed then notify("unread") end
end

function M.reset()
  M.clearToken()
  M.clearAccount()
  M.unreadCount = 0
end

-- 启动时恢复
function M.bootstrap()
  M.loadToken()
  M.loadAccountCache()
end

return M
