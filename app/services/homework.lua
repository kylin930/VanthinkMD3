-- 作业服务：列表、详情、练习项排行榜。
-- 接口与参数依据原项目实际调用：
--   GET /api/homework/student/getHomeworkList?page&page_size&time&degree
--   GET /api/homework/student/getHomeworkInfo?homework_id
--   GET /api/homework/student/getTestbankRankList?homework_id&testbank_id

local config = require "app.config"
local http = require "app.services.http"
local formatter = require "app.utils.formatter"

local M = {}

local function normalizeList(data)
  local list = {}
  if type(data) == "table" and type(data.list) == "table" then
    for index, item in ipairs(data.list) do
      list[index] = item
    end
  end
  return list
end

function M.fetchList(opts, callback)
  local page = opts.page or 1
  local pageSize = opts.pageSize or config.PAGE_SIZE
  return http.request({
    url = config.API.homeworkList,
    method = "GET",
    query = {
      { "page", page },
      { "page_size", pageSize },
      { "time", opts.time or "all" },
      { "degree", opts.degree or "all" },
    },
    auth = true,
    tag = "homework/list",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "作业列表加载失败", result)
      return
    end
    local data = result.data or {}
    local list = normalizeList(data)
    local total = tonumber(data.total) or #list
    callback(true, {
      list = list,
      total = total,
      page = page,
      hasMore = #list > 0 and (#list == pageSize) and (#list < total or total == 0),
    }, result)
  end)
end

function M.fetchDetail(homeworkId, callback)
  return http.request({
    url = config.API.homeworkInfo,
    method = "GET",
    query = { { "homework_id", homeworkId } },
    auth = true,
    tag = "homework/detail",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "作业详情加载失败", result)
      return
    end
    local data = result.data
    if type(data) ~= "table" then
      callback(false, "作业详情数据格式异常", result)
      return
    end
    callback(true, data, result)
  end)
end

function M.fetchRankList(homeworkId, testbankId, callback)
  return http.request({
    url = config.API.testbankRankList,
    method = "GET",
    query = {
      { "homework_id", homeworkId },
      { "testbank_id", testbankId },
    },
    auth = true,
    tag = "homework/rank",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "排行榜加载失败", result)
      return
    end
    local data = result.data or {}
    local entry = nil
    if type(data.list) == "table" and type(data.list[1]) == "table" then
      entry = data.list[1]
    end
    local rankList = {}
    if entry ~= nil and type(entry.rank_list) == "table" then
      for index, item in ipairs(entry.rank_list) do
        rankList[index] = item
      end
    end
    callback(true, {
      list = rankList,
      self = entry and entry["self"] or nil,
    }, result)
  end)
end

-- 提交「练习完成」记录：POST /api/game/saveScore
-- 依据原项目实际字段：
--   * spend_time 由调用方给出：自动操作时是排行榜第 1 名耗时 + 随机 2~4 秒
--     （见 referenceSeconds），手动录入时是用户填写的实际耗时；
--   * end_time 由开始时间（当前时间）加耗时推算；
--   * scores / correct_rate / wrong_exercises 保持服务端要求的空值占位，
--     不伪造分数与准确率。
-- opts = { gameId, homeworkId, testbankId, seconds }
function M.submitCompletion(opts, callback)
  local raw = tonumber(opts.seconds)
  if raw == nil or raw ~= math.floor(raw)
    or raw < config.SPEND_TIME_MIN or raw > config.SPEND_TIME_MAX then
    callback(false, string.format("耗时必须是 %d ~ %d 之间的整数秒",
      config.SPEND_TIME_MIN, config.SPEND_TIME_MAX))
    return nil
  end
  local seconds = raw

  local parts = formatter.nowParts()
  local function formatTime(partsValue)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
      partsValue.year, partsValue.month, partsValue.day,
      partsValue.hour, partsValue.minute, partsValue.second)
  end

  local Calendar = luajava.bindClass("java.util.Calendar")
  local calendar = Calendar.getInstance()
  local startTime = formatTime(parts)
  calendar.add(Calendar.SECOND, seconds)
  local endParts = {
    year = calendar.get(Calendar.YEAR),
    month = calendar.get(Calendar.MONTH) + 1,
    day = calendar.get(Calendar.DAY_OF_MONTH),
    hour = calendar.get(Calendar.HOUR_OF_DAY),
    minute = calendar.get(Calendar.MINUTE),
    second = calendar.get(Calendar.SECOND),
  }
  local endTime = formatTime(endParts)
  local spendTime = formatter.spendTime(seconds)

  return http.request({
    url = config.API.saveScore,
    method = "POST",
    form = {
      record_id = "0",
      game_id = opts.gameId,
      homework_id = opts.homeworkId,
      testbank_id = opts.testbankId,
      start_time = startTime,
      end_time = endTime,
      spend_time = spendTime,
      wrong_exercises = "[]",
      scores = "0",
      stars = "0",
      correct_rate = "0",
    },
    auth = true,
    tag = "homework/saveScore",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "提交失败")
      return
    end
    callback(true, result.body)
  end)
end

-- 达标判定的正确率阈值（原项目规则：达标模式要求满分 100，普通模式要求 80）
function M.passThreshold(item)
  if M.isStandardMode(item) then return config.ACCURACY_STANDARD end
  return config.ACCURACY_NORMAL
end

-- 完成状态判定：沿用原项目逻辑，`self.is_answered` 为 1 且 `self.accuracy`
-- 达到该练习的达标阈值时视为已完成，可跳过。
function M.isCompleted(item, selfInfo)
  if type(selfInfo) ~= "table" then return false end
  local answered = selfInfo.is_answered
  if not (answered == 1 or answered == "1" or answered == true) then return false end
  local accuracy = tonumber(selfInfo.accuracy)
  if accuracy == nil then return false end
  return accuracy >= M.passThreshold(item)
end

-- 随机偏移秒数（2~4 秒），用于在榜首耗时基础上生成提交参考值
function M.referenceJitter()
  local min = config.SPEND_TIME_JITTER_MIN
  local max = config.SPEND_TIME_JITTER_MAX
  local ok, value = pcall(function() return math.random(min, max) end)
  if not ok or type(value) ~= "number" then return min end
  return math.floor(value)
end

-- 读取排行榜参考耗时：第 1 名（榜首）耗时 + 随机 2~4 秒。
-- 返回 seconds, source 或 nil, reason。
-- 榜首数据缺失/无效时返回 nil 与原因，调用方不得自行补默认值。
function M.referenceSeconds(rankList, jitter)
  if type(rankList) ~= "table" then
    return nil, "排行榜数据为空"
  end
  local entry = rankList[1]
  if type(entry) ~= "table" then
    return nil, "排行榜第 1 名不存在"
  end
  local base = formatter.parseSeconds(entry.spend_time)
  if base == nil then
    return nil, "排行榜第 1 名耗时无效"
  end
  if base < config.SPEND_TIME_MIN or base > config.SPEND_TIME_MAX then
    return nil, string.format("排行榜第 1 名耗时超出允许范围（%d 秒）", base)
  end
  local delta = tonumber(jitter) or M.referenceJitter()
  local seconds = base + delta
  if seconds > config.SPEND_TIME_MAX then
    return nil, string.format("加上随机偏移后超出允许范围（%d 秒）", seconds)
  end
  local account = type(entry.account) == "table" and entry.account or {}
  return seconds, {
    nickname = tostring(account.nickname or "同学"),
    raw = tostring(entry.spend_time),
    base = base,
    jitter = delta,
  }
end

-- 判定练习项是否为语音类（原项目规则：名称含“读”但不是“阅读理解”）
function M.isVoicePractice(item)
  local game = type(item) == "table" and item.game or nil
  local name = type(game) == "table" and tostring(game.name or "") or ""
  if name == "" then return false end
  local hasRead = string.find(name, "读", 1, true) ~= nil
  return hasRead and name ~= "阅读理解"
end

-- 达标模式判定：存在 standard 字段
function M.isStandardMode(item)
  return type(item) == "table" and item.standard ~= nil
end

return M
