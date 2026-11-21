-- 作业批量自动执行引擎（单个作业「一键完成」与多选作业「批量操作」共用）。
-- 流程：
--   1. 逐个获取选中作业的详情；
--   2. 汇总全部练习，语音练习直接跳过并计入统计；
--   3. 串行处理每个练习：查询排行榜 → 读取自己的完成状态 → 取排行榜第 1 名耗时
--      加随机 2~4 秒作为 spend_time → 未达标且有有效参考值时调用 submitCompletion 提交；
--   4. 一份作业处理完成后、开始下一份作业前随机等待 3~6 秒（练习项之间不等待）；
--   5. 逐项记录结果与失败原因，全部结束后回调 onDone。
--
-- 约束（与实现对应）：
--   * 网络接口全部复用 homeworkService，不另写一套；
--   * 全程串行，同一时刻只有一个请求在途；
--   * 随机只用于「榜首耗时 +2~4 秒」与「作业之间的 3~6 秒间隔」，不用于伪造分数；
--   * 单项失败不影响后续项目；请求失败后先复核服务端状态再判定；
--   * 取消只阻止尚未开始的队列项目，已发出的请求按其真实结果记账。

local config = require "app.config"
local homeworkService = require "app.services.homework"

local M = {}

-- 结果状态 → 中文标签（UI 与结果报告共用）
M.LABEL = {
  success = "提交成功",
  failed = "提交失败",
  skippedCompleted = "已完成跳过",
  skippedVoice = "语音跳过",
  noReference = "无有效耗时",
  cancelled = "已取消",
}

-- 瞬时错误：先复核服务端状态 / 重试一次再判定
local TRANSIENT_KINDS = {
  timeout = true,
  connect = true,
  dns = true,
  unknown = true,
}

local function practiceName(practice)
  local game = type(practice.game) == "table" and practice.game or {}
  local gameName = tostring(game.name or "练习")
  local name = tostring(practice.name or "")
  if name == "" then return gameName end
  return string.format("%s · %s", gameName, name)
end

local function newStats()
  return {
    homeworkCount = 0,
    practiceCount = 0,
    queueCount = 0,
    success = 0,
    failed = 0,
    skippedVoice = 0,
    skippedCompleted = 0,
    noReference = 0,
    cancelled = 0,
  }
end

-- 把下一步调度到消息队列，避免同步回调路径上递归过深。
-- 1ms 只是调度间隔，不是“伪装真人”的等待。
local function nextTick(fn)
  local ok = pcall(function() activity.delay(1, fn) end)
  if not ok then fn() end
end

function M.create(opts)
  local o = opts or {}

  local batch = {
    running = false,
    finished = false,
    cancelled = false,
    phase = "idle", -- idle / detail / running / gap / done / cancelled
    stats = newStats(),
    results = {},
    errors = {}, -- 作业详情获取失败记录
    current = nil,
    currentIndex = 0,
    currentTotal = 0,
    gapSeconds = 0, -- 作业之间本次实际等待的秒数（仅用于展示）
    onUpdate = o.onUpdate,
    onDone = o.onDone,
    homeworks = {},
  }

  for _, item in ipairs(o.homeworks or {}) do
    if type(item) == "table" and item.id ~= nil then
      batch.homeworks[#batch.homeworks + 1] = item
    end
  end
  batch.stats.homeworkCount = #batch.homeworks

  local queue = {}
  local submitted = {}
  local homeworkIndex = 0
  local taskIndex = 0
  local lastHomeworkId = nil

  local function emit()
    if batch.onUpdate then pcall(batch.onUpdate, batch) end
  end

  local function record(task, status, reason, seconds, reference)
    batch.results[#batch.results + 1] = {
      homeworkId = task.homeworkId,
      homeworkName = task.homeworkName,
      testbankId = task.testbankId,
      practiceName = task.practiceName,
      status = status,
      reason = reason,
      seconds = seconds,
      reference = reference,
    }
  end

  local function finishRun()
    if batch.finished then return end
    batch.finished = true
    batch.running = false
    batch.current = nil
    if batch.cancelled then
      batch.phase = "cancelled"
      for index = taskIndex + 1, #queue do
        local task = queue[index]
        batch.stats.cancelled = batch.stats.cancelled + 1
        record(task, "cancelled", "任务已取消，未执行")
      end
      taskIndex = #queue
    else
      batch.phase = "done"
    end
    emit()
    if batch.onDone then pcall(batch.onDone, batch) end
  end

  -- 复核服务端是否已记录该练习（用于超时/连接失败后的二次判定）
  local function recheckCompleted(task, callback)
    homeworkService.fetchRankList(task.homeworkId, task.testbankId, function(ok, data)
      if not ok then return callback(false) end
      callback(homeworkService.isCompleted(task.practice, data["self"]))
    end)
  end

  local stepTask

  local function processTask(task, next)
    local key = tostring(task.homeworkId) .. ":" .. tostring(task.testbankId)

    local function afterRank(ok, data)
      if not ok then
        batch.stats.noReference = batch.stats.noReference + 1
        record(task, "noReference", "排行榜查询失败：" .. tostring(data))
        emit()
        return next()
      end

      local selfInfo = data["self"]
      if homeworkService.isCompleted(task.practice, selfInfo) then
        batch.stats.skippedCompleted = batch.stats.skippedCompleted + 1
        record(task, "skippedCompleted", string.format("已完成（正确率 %s%%，达标要求 %d%%）",
          tostring(selfInfo.accuracy), homeworkService.passThreshold(task.practice)))
        emit()
        return next()
      end

      local seconds, reference = homeworkService.referenceSeconds(data.list)
      if seconds == nil then
        -- reference 在失败时是具体原因字符串
        batch.stats.noReference = batch.stats.noReference + 1
        record(task, "noReference", tostring(reference))
        emit()
        return next()
      end

      if submitted[key] then
        -- 本次任务中已经提交过，不重复提交
        record(task, "success", "本次已提交，未重复执行", seconds, reference)
        emit()
        return next()
      end

      submitted[key] = true
      batch.current = {
        homeworkName = task.homeworkName,
        practiceName = task.practiceName,
        stage = "submit",
        seconds = seconds,
        reference = reference,
      }
      emit()

      homeworkService.submitCompletion({
        gameId = task.gameId,
        homeworkId = task.homeworkId,
        testbankId = task.testbankId,
        seconds = seconds,
      }, function(ok2, message, result)
        if ok2 then
          batch.stats.success = batch.stats.success + 1
          record(task, "success", nil, seconds, reference)
          emit()
          return next()
        end
        -- 提交失败时先复核服务端状态：超时可能已经落库，不能直接报失败
        recheckCompleted(task, function(completed)
          if completed then
            batch.stats.success = batch.stats.success + 1
            record(task, "success", "请求异常，但服务端已完成", seconds, reference)
          else
            batch.stats.failed = batch.stats.failed + 1
            local reason = tostring(message or "提交失败")
            local kind = type(result) == "table" and result.kind or nil
            if kind == "timeout" then
              reason = "提交超时，服务端未记录"
            end
            record(task, "failed", reason, seconds, reference)
          end
          emit()
          next()
        end)
      end)
    end

    homeworkService.fetchRankList(task.homeworkId, task.testbankId, function(ok, data, result)
      if ok then return afterRank(true, data) end
      local kind = type(result) == "table" and result.kind or nil
      if not TRANSIENT_KINDS[kind] then
        return afterRank(false, data)
      end
      -- 瞬时错误：串行重试一次，仍失败才记为无有效排行榜数据
      homeworkService.fetchRankList(task.homeworkId, task.testbankId, function(ok2, data2)
        afterRank(ok2, ok2 and data2 or (data or "排行榜查询失败"))
      end)
    end)
  end

  local function runTask(task)
    batch.phase = "running"
    batch.currentIndex = taskIndex
    batch.currentTotal = #queue
    batch.current = {
      homeworkName = task.homeworkName,
      practiceName = task.practiceName,
      stage = "rank",
    }
    emit()
    processTask(task, function() nextTick(stepTask) end)
  end

  -- 作业之间的随机等待（3~6 秒）。只在「上一份作业处理完、开始下一份作业」时执行一次，
  -- 同一份作业内的练习项之间不等待。
  local function gapBetweenHomeworks(callback)
    local min = config.HOMEWORK_GAP_MIN_MS
    local max = config.HOMEWORK_GAP_MAX_MS
    local okRandom, value = pcall(function() return math.random(min, max) end)
    local delayMs = okRandom and tonumber(value) or min
    batch.gapSeconds = math.floor(delayMs / 1000 + 0.5)
    local okDelay = pcall(function() activity.delay(delayMs, callback) end)
    if not okDelay then callback() end
  end

  function stepTask()
    if batch.cancelled then return finishRun() end
    taskIndex = taskIndex + 1
    local task = queue[taskIndex]
    if task == nil then return finishRun() end

    -- 切换到下一份作业：先等待，再继续该作业的练习项
    if lastHomeworkId ~= nil and lastHomeworkId ~= task.homeworkId then
      batch.phase = "gap"
      batch.current = {
        homeworkName = task.homeworkName,
        practiceName = string.format("作业已完成，等待 %d 秒后继续", batch.gapSeconds or 0),
        stage = "gap",
      }
      emit()
      lastHomeworkId = task.homeworkId
      return gapBetweenHomeworks(function()
        if batch.cancelled then return finishRun() end
        runTask(task)
      end)
    end

    lastHomeworkId = task.homeworkId
    runTask(task)
  end

  local function stepDetail()
    if batch.cancelled then return finishRun() end
    homeworkIndex = homeworkIndex + 1
    local homework = batch.homeworks[homeworkIndex]

    if homework == nil then
      batch.stats.queueCount = #queue
      batch.phase = "running"
      batch.currentIndex = 0
      batch.current = nil
      emit()
      return nextTick(stepTask)
    end

    batch.phase = "detail"
    batch.currentIndex = homeworkIndex
    batch.currentTotal = #batch.homeworks
    batch.current = {
      homeworkName = tostring(homework.name or homework.id),
      practiceName = "正在获取作业详情",
      stage = "detail",
    }
    emit()

    homeworkService.fetchDetail(homework.id, function(ok, data)
      if not ok then
        batch.errors[#batch.errors + 1] = {
          homeworkName = tostring(homework.name or homework.id),
          reason = tostring(data),
        }
        emit()
        return nextTick(stepDetail)
      end

      local detail = type(data) == "table" and data or {}
      local homeworkName = tostring(detail.name or homework.name or homework.id)
      local practices = type(detail.testbanks) == "table" and detail.testbanks or {}

      for _, practice in ipairs(practices) do
        batch.stats.practiceCount = batch.stats.practiceCount + 1
        local task = {
          homeworkId = detail.id or homework.id,
          homeworkName = homeworkName,
          testbankId = practice.id,
          gameId = type(practice.game) == "table" and practice.game.id or nil,
          practice = practice,
          practiceName = practiceName(practice),
        }
        if homeworkService.isVoicePractice(practice) then
          batch.stats.skippedVoice = batch.stats.skippedVoice + 1
          record(task, "skippedVoice", "语音练习，自动跳过")
        else
          queue[#queue + 1] = task
        end
      end

      emit()
      nextTick(stepDetail)
    end)
  end

  function batch.start()
    if batch.running or batch.finished then return batch end
    batch.running = true
    batch.cancelled = false
    batch.phase = "detail"
    emit()
    nextTick(stepDetail)
    return batch
  end

  function batch.cancel()
    if batch.finished then return batch end
    batch.cancelled = true
    emit()
    return batch
  end

  if o.start ~= false then batch.start() end
  return batch
end

return M
