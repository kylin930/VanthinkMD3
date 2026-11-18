-- 非敏感偏好设置：基于 NeLuaJ+ SharedData（SharedPreferences）持久化。
-- 仅存字符串，类型转换在此模块完成。

local M = {}

local PREFIX = "vt_pref_"

local function key(k)
  return PREFIX .. k
end

function M.getString(name, fallback)
  local ok, value = pcall(function() return activity.getSharedData(key(name)) end)
  if not ok or value == nil then return fallback end
  local text = tostring(value)
  if text == "" then return fallback end
  return text
end

function M.setString(name, value)
  return pcall(function() activity.setSharedData(key(name), tostring(value)) end)
end

function M.getBool(name, fallback)
  local text = M.getString(name, nil)
  if text == nil then return fallback end
  return text == "true" or text == "1"
end

function M.setBool(name, value)
  return M.setString(name, value and "true" or "false")
end

function M.getInt(name, fallback)
  local text = M.getString(name, nil)
  if text == nil then return fallback end
  local number = tonumber(text)
  if number == nil then return fallback end
  return math.floor(number)
end

function M.setInt(name, value)
  return M.setString(name, tostring(math.floor(value or 0)))
end

function M.remove(name)
  return M.setString(name, "")
end

return M
