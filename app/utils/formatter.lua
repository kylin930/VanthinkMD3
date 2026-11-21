-- 展示层格式化：时间、百分比、数字、耗时。
-- 服务端时间格式为 "YYYY-MM-DD HH:mm:ss"，按原项目行为视作可直接展示的本地时间。

local M = {}

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function isLeap(year)
  return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
end

local function daysInMonth(year, month)
  if month == 2 and isLeap(year) then return 29 end
  return MONTH_DAYS[month] or 30
end

-- 解析 "YYYY-MM-DD HH:mm:ss" 或 "YYYY-MM-DD"
function M.parseDateTime(text)
  if type(text) ~= "string" then return nil end
  local y, mo, d, h, mi, s = string.match(text,
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d):(%d%d)")
  if y == nil then
    y, mo, d = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y == nil then return nil end
    h, mi, s = "0", "0", "0"
  end
  return {
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), minute = tonumber(mi), second = tonumber(s),
  }
end

function M.nowParts()
  local ok, parts = pcall(function()
    local Calendar = luajava.bindClass("java.util.Calendar")
    local calendar = Calendar.getInstance()
    return {
      year = calendar.get(Calendar.YEAR),
      month = calendar.get(Calendar.MONTH) + 1,
      day = calendar.get(Calendar.DAY_OF_MONTH),
      hour = calendar.get(Calendar.HOUR_OF_DAY),
      minute = calendar.get(Calendar.MINUTE),
      second = calendar.get(Calendar.SECOND),
    }
  end)
  if ok and parts ~= nil then return parts end
  return { year = 2025, month = 1, day = 1, hour = 0, minute = 0, second = 0 }
end

-- 两个时间点相差的天数（0 = 今天，1 = 昨天 ...）
local function dayDiff(fromParts, toParts)
  local function toEpoch(p)
    local days = 0
    local year = p.year
    for y = 1970, year - 1 do
      days = days + (isLeap(y) and 366 or 365)
    end
    for m = 1, p.month - 1 do
      days = days + daysInMonth(year, m)
    end
    days = days + p.day - 1
    return days
  end
  return toEpoch(toParts) - toEpoch(fromParts)
end

-- 友好时间：今天 14:05 / 昨天 / 3 天前 / 2025-03-04
function M.friendlyTime(text)
  local parts = M.parseDateTime(text)
  if parts == nil then
    return tostring(text or "")
  end
  local now = M.nowParts()
  local diff = dayDiff(parts, now)
  local hm = string.format("%02d:%02d", parts.hour, parts.minute)
  if diff == 0 then
    return "今天 " .. hm
  elseif diff == 1 then
    return "昨天 " .. hm
  elseif diff > 1 and diff < 7 then
    return diff .. " 天前"
  elseif diff < 0 and diff > -7 then
    return "即将开始"
  end
  return string.format("%04d-%02d-%02d", parts.year, parts.month, parts.day)
end

-- mm:ss / h:mm:ss
function M.duration(seconds)
  local total = tonumber(seconds) or 0
  if total < 0 then total = 0 end
  total = math.floor(total)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

-- 解析排行榜耗时 "m:ss" / "mm:ss"
function M.parseDuration(text)
  if type(text) ~= "string" then return 0 end
  local m, s = string.match(text, "^(%d+):(%d+)$")
  if m == nil then
    local number = tonumber(text)
    return number and math.floor(number) or 0
  end
  return tonumber(m) * 60 + tonumber(s)
end

-- 严格解析耗时："m:ss" / "mm:ss" / "h:mm:ss" / 纯秒数。
-- 与 parseDuration 的区别：无法解析、字段缺失、非正数一律返回 nil，
-- 调用方必须显式处理“没有有效耗时”，不得用默认值补位。
function M.parseSeconds(value)
  if type(value) == "number" then
    if value <= 0 or value ~= math.floor(value) then return nil end
    return value
  end
  if type(value) ~= "string" then return nil end
  local text = string.match(value, "^%s*(.-)%s*$") or ""
  if text == "" then return nil end
  local h, m, s = string.match(text, "^(%d+):(%d+):(%d+)$")
  if h ~= nil then
    local total = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    if total <= 0 then return nil end
    return total
  end
  m, s = string.match(text, "^(%d+):(%d+)$")
  if m ~= nil then
    local total = tonumber(m) * 60 + tonumber(s)
    if total <= 0 then return nil end
    return total
  end
  local number = tonumber(text)
  if number == nil or number <= 0 or number ~= math.floor(number) then return nil end
  return number
end

-- 把秒数格式化为 "HH:MM:SS"（与 saveScore 的 spend_time 字段一致）
function M.spendTime(seconds)
  local total = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format("%02d:%02d:%02d",
    math.floor(total / 3600), math.floor((total % 3600) / 60), total % 60)
end

function M.percent(value)
  local number = tonumber(value)
  if number == nil then return "0%" end
  if number > 0 and number <= 1 then
    -- 服务端部分接口使用 0~1 比例
    number = number * 100
  end
  return string.format("%d%%", math.floor(number + 0.5))
end

function M.number(value)
  local number = tonumber(value) or 0
  if number >= 10000 then
    return string.format("%.1fw", number / 10000)
  end
  if number >= 1000 then
    return string.format("%.1fk", number / 1000)
  end
  return tostring(math.floor(number))
end

function M.int(value)
  local number = tonumber(value)
  if number == nil then return "0" end
  return tostring(math.floor(number))
end

-- "MM/DD"（统计图 X 轴）
function M.shortDate(text)
  local parts = M.parseDateTime(text)
  if parts == nil then return tostring(text or "") end
  return string.format("%02d/%02d", parts.month, parts.day)
end

-- 教师/班级描述：与原项目文案语义一致，但重新组织
function M.homeworkSummary(detail)
  if type(detail) ~= "table" then return "" end
  local teacher = detail.teacher_name or "老师"
  local className = detail.vanclass and detail.vanclass.name or "未知班级"
  local typeName = detail["type"] and detail["type"].name or "普通模式"
  local created = M.friendlyTime(detail.created_at)
  return string.format("%s · %s · %s", teacher, className, typeName), created
end

return M
