-- 作业服务：列表、详情、练习项排行榜。
-- 接口与参数依据原项目实际调用：
--   GET /api/homework/student/getHomeworkList?page&page_size&time&degree
--   GET /api/homework/student/getHomeworkInfo?homework_id
--   GET /api/homework/student/getTestbankRankList?homework_id&testbank_id

local config = require "app.config"
local http = require "app.services.http"

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
-- 依据原项目实际字段。与原项目的差别（合规性修正）：
--   * spend_time 由用户输入的真实耗时得到，不做随机偏移；
--   * end_time 由服务端时间的合理推算得出（开始时间 = 当前时间，结束 = 开始 + 耗时）；
--   * scores / correct_rate / wrong_exercises 保持服务端要求的空值占位，
--     不伪造分数与准确率。
-- opts = { gameId, homeworkId, testbankId, seconds }
function M.submitCompletion(opts, callback)
  local seconds = math.floor(tonumber(opts.seconds) or 0)
  if seconds <= 0 then
    callback(false, "耗时必须大于 0 秒")
    return nil
  end

  local parts = require "app.utils.formatter".nowParts()
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
  local spendTime = string.format("%02d:%02d:%02d",
    math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)

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
