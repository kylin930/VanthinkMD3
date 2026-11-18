-- 日志工具：写 Android Logcat，不使用 print（print 在运行时会产生界面提示，
-- 高频调用会遮挡界面并造成闪烁）。所有敏感值在输出前遮蔽。

local M = {}

M.tag = "VanthinkMD3"
-- 详细日志默认关闭；调试时置为 true 也只写 Logcat，不影响界面
M.debugEnabled = false

local Log = luajava.bindClass("android.util.Log")

local function redact(text)
  if type(text) ~= "string" then return text end
  -- 遮蔽形如 token 的长串（>= 24 位连续字母数字）
  return (string.gsub(text, "([%w_%-%.])+", function(match)
    if #match >= 24 then
      return string.sub(match, 1, 4) .. "***"
    end
    return match
  end))
end

local function emit(level, message)
  if level == "D" and not M.debugEnabled then return end
  local text = redact(tostring(message))
  pcall(function()
    if level == "E" then
      Log.e(M.tag, text)
    elseif level == "W" then
      Log.w(M.tag, text)
    elseif level == "I" then
      Log.i(M.tag, text)
    else
      Log.d(M.tag, text)
    end
  end)
end

function M.d(message) emit("D", message) end
function M.i(message) emit("I", message) end
function M.w(message) emit("W", message) end
function M.e(message) emit("E", message) end

-- 遮蔽手机号：138****8000
function M.maskPhone(phone)
  local text = tostring(phone or "")
  if #text < 7 then return "***" end
  return string.sub(text, 1, 3) .. "****" .. string.sub(text, -4)
end

return M
