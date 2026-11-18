-- 统计服务：POST /api/vanclass/getVanclassStudentReport（JSON）
--   { student_id, year, month } -> data.practice/exercise/time/photo_homework/pl_data/list

local config = require "app.config"
local http = require "app.services.http"
local state = require "app.state"

local M = {}

local function toNumber(value)
  local number = tonumber(value)
  if number == nil then return 0 end
  return number
end

local function normalizeMetric(raw)
  local metric = type(raw) == "table" and raw or {}
  return {
    count = toNumber(metric.count),
    avg = toNumber(metric.avg),
    monthAvg = toNumber(metric.month_avg),
  }
end

function M.fetchReport(opts, callback)
  local account = state.account
  local studentId = nil
  if type(account) == "table" then
    studentId = account.id
  end
  if studentId == nil then
    callback(false, "尚未获取到账号信息，请重新登录", { kind = "local" })
    return nil
  end

  return http.request({
    url = config.API.studentReport,
    method = "POST",
    json = {
      student_id = studentId,
      year = opts.year,
      month = opts.month,
    },
    auth = true,
    tag = "statistics/report",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "统计数据加载失败", result)
      return
    end
    local data = result.data
    if type(data) ~= "table" then
      callback(false, "统计数据格式异常", result)
      return
    end

    local daily = {}
    if type(data.list) == "table" then
      for _, item in ipairs(data.list) do
        if type(item) == "table" then
          daily[#daily + 1] = {
            day = tostring(item.day or ""),
            score = toNumber(item.score),
            time = toNumber(item.time),
          }
        end
      end
    end

    local plData = type(data.pl_data) == "table" and data.pl_data or {}
    callback(true, {
      practice = normalizeMetric(data.practice),
      exercise = normalizeMetric(data.exercise),
      days = normalizeMetric(data.time),
      photo = normalizeMetric(data.photo_homework),
      pl = {
        startTime = plData.start_time,
        totalTime = toNumber(plData.total_time),
        avgTime = toNumber(plData.avg_time),
      },
      daily = daily,
      studentName = data.student_name,
    }, result)
  end)
end

return M
