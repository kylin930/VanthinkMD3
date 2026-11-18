-- 输入校验：手机号、密码、年份月份、颜色值。
-- 只做前端体验性校验，不作为安全边界。

local M = {}

function M.trim(text)
  if type(text) ~= "string" then return "" end
  return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- 中国大陆手机号：1 开头 11 位
function M.isPhone(text)
  local value = M.trim(text)
  return string.match(value, "^1%d%d%d%d%d%d%d%d%d%d$") ~= nil
end

function M.isPassword(text)
  local value = M.trim(text)
  return #value >= 1, value
end

function M.isYear(text)
  local value = tonumber(M.trim(text))
  if value == nil then return false end
  if value < 2000 or value > 2100 then return false end
  return math.floor(value) == value
end

function M.isMonth(text)
  local value = tonumber(M.trim(text))
  if value == nil then return false end
  if value < 1 or value > 12 then return false end
  return math.floor(value) == value
end

-- 支持 #RRGGBB / RRGGBB，返回 0xFFRRGGBB
function M.parseColor(text)
  local value = M.trim(text)
  value = string.gsub(value, "^#", "")
  if string.match(value, "^%x%x%x%x%x%x$") == nil then return nil end
  return tonumber("FF" .. value, 16)
end

function M.colorToHex(color)
  local value = math.floor(color or 0) % 0x1000000
  return string.format("%06X", value)
end

-- 手机号遮蔽，用于展示
function M.maskPhone(phone)
  local value = M.trim(phone)
  if #value < 7 then return value end
  return string.sub(value, 1, 3) .. "****" .. string.sub(value, -4)
end

return M
