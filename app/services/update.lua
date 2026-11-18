-- 更新服务：GET https://zxzjverlog.930390.xyz/api/version
--   -> { version, update_time, added[], improved[], fixed[], note }
-- 该接口位于第三方域名，属于可选能力：任何失败都不得影响应用启动与主流程。

local config = require "app.config"
local http = require "app.services.http"
local pref = require "app.storage.preferences"

local M = {}

local ACK_KEY = "update_ack_version"

local function toList(raw)
  local list = {}
  if type(raw) == "table" then
    for _, item in ipairs(raw) do
      list[#list + 1] = tostring(item)
    end
  end
  return list
end

function M.fetch(callback)
  return http.request({
    url = config.THIRD_PARTY.updateLog,
    method = "GET",
    auth = false,
    tag = "update/version",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "更新服务不可用", result)
      return
    end
    local body = result.body
    if type(body) ~= "table" then
      callback(false, "更新信息格式异常", result)
      return
    end
    callback(true, {
      version = tostring(body.version or ""),
      updateTime = body.update_time or "未指定",
      added = toList(body.added),
      improved = toList(body.improved),
      fixed = toList(body.fixed),
      note = body.note,
    }, result)
  end)
end

function M.ackVersion(version)
  pref.setString(ACK_KEY, tostring(version or ""))
end

function M.ackedVersion()
  return pref.getString(ACK_KEY, nil)
end

-- 是否为新版本：仅当服务端版本与上次确认版本不同（沿用原项目判定方式）
function M.isNewVersion(version)
  if version == nil or tostring(version) == "" then return false end
  return M.ackedVersion() ~= tostring(version)
end

return M
