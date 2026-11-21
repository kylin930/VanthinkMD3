-- v0.2.4 批量操作测试（开发期工具，不参与运行，不随打包产物发布）
--
-- 覆盖范围：
--   A. 纯逻辑：耗时解析、排行榜第 1 名取值、达标判定、语音练习识别
--   B. 批量引擎：正常流程、完成跳过、语音跳过、无有效耗时、提交失败、
--      排行榜超时重试、提交超时后复核、取消任务、不重复提交、同名练习按真实 ID 区分
--   C. 界面：作业首页多选（30 上限 / 全选 / 清空）、批量操作页进度与结果、
--      作业详情「一键完成」入口、关于页项目来源与致谢文案
--
-- 全程使用桩数据替换服务层，不发起任何网络请求。
-- 用法：在 NeLuaJ+ 中直接运行本文件（不要作为工程入口）。
-- 输出：_test_batch_v024.txt

local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_test_batch_v024.txt"

local lines = {}
local passCount, failCount = 0, 0

local function log(text) lines[#lines + 1] = tostring(text or "") end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

print = function(...)
  local parts = {}
  for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
  log("      LOG " .. table.concat(parts, " "):gsub("\n", " "):sub(1, 300))
end

local function pass(label, detail)
  passCount = passCount + 1
  log(string.format("PASS  %s%s", label, detail and ("  [" .. tostring(detail) .. "]") or ""))
  flush()
end

local function fail(label, detail)
  failCount = failCount + 1
  log(string.format("FAIL  %s%s", label, detail and ("  [" .. tostring(detail) .. "]") or ""))
  flush()
end

local function check(label, ok, detail)
  if ok then pass(label, detail) else fail(label, detail) end
  return ok and true or false
end

-- ===== 依赖 =====
local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
local state = require "app.state"
local config = require "app.config"
local formatter = require "app.utils.formatter"
local homeworkService = require "app.services.homework"
local batchService = require "app.services.homework_batch"

pcall(function() theme.bootstrap() end)

-- 只改内存里的登录态，不写安全存储（避免覆盖本机真实 Token）
state.token = "v024_test_token"
state.account = { id = 1, nickname = "测试账号" }

local function waitFor(predicate, callback, timeoutMs, intervalMs)
  local interval = intervalMs or 50
  local limit = timeoutMs or 6000
  local elapsed = 0
  local function tick()
    local ok, result = pcall(predicate)
    if ok and result then return callback(true) end
    elapsed = elapsed + interval
    if elapsed >= limit then return callback(false) end
    activity.delay(interval, tick)
  end
  activity.delay(interval, tick)
end

-- ===== 桩数据 =====
local detailData = {}
local rankBehavior = {}
local rankCalls = {}
local submitBehavior = {}
local submitCalls = {}
local submitSeconds = {}

local function practice(id, name, gameName, extra)
  local item = { id = id, name = name, game = { id = id * 10, name = gameName } }
  for key, value in pairs(extra or {}) do item[key] = value end
  return item
end

homeworkService.fetchDetail = function(homeworkId, callback)
  local detail = detailData[tostring(homeworkId)]
  if detail == nil then
    callback(false, "作业详情加载失败")
    return nil
  end
  callback(true, detail)
  return nil
end

homeworkService.fetchRankList = function(homeworkId, testbankId, callback)
  local key = tostring(homeworkId) .. ":" .. tostring(testbankId)
  rankCalls[key] = (rankCalls[key] or 0) + 1
  local behavior = rankBehavior[key]
  if behavior == nil then
    callback(true, { list = {} })
    return nil
  end
  if behavior.failKind ~= nil and (behavior.failTimes == nil or rankCalls[key] <= behavior.failTimes) then
    callback(false, "请求超时，请稍后重试", { ok = false, kind = behavior.failKind })
    return nil
  end
  local payload = behavior
  if type(behavior.sequence) == "table" then
    local index = math.max(1, math.min(rankCalls[key] - (behavior.failTimes or 0), #behavior.sequence))
    payload = behavior.sequence[index]
  end
  callback(true, { list = payload.list or {}, self = payload.selfInfo })
  return nil
end

-- 保存真实实现，用于校验耗时参数（不做任何网络请求）
local realSubmitCompletion = homeworkService.submitCompletion

homeworkService.submitCompletion = function(opts, callback)
  local key = tostring(opts.homeworkId) .. ":" .. tostring(opts.testbankId)
  submitCalls[key] = (submitCalls[key] or 0) + 1
  submitSeconds[key] = opts.seconds
  local behavior = submitBehavior[key]
  local function respond()
    if behavior ~= nil and behavior.ok == false then
      callback(false, behavior.message or "提交失败", { ok = false, kind = behavior.kind })
      return
    end
    callback(true, { errcode = 0 })
  end
  if behavior ~= nil and behavior.delayMs ~= nil then
    activity.delay(behavior.delayMs, respond)
    return nil
  end
  respond()
  return nil
end

local function resetStubs()
  detailData = {}
  rankBehavior = {}
  rankCalls = {}
  submitBehavior = {}
  submitCalls = {}
  submitSeconds = {}
end

local function rank(selfInfo, list, extra)
  local value = { selfInfo = selfInfo, list = list }
  for key, item in pairs(extra or {}) do value[key] = item end
  return value
end

-- ===== A. 纯逻辑 =====
log("=== A. 纯逻辑校验 ===")

check("parseSeconds m:ss", formatter.parseSeconds("1:35") == 95, tostring(formatter.parseSeconds("1:35")))
check("parseSeconds mm:ss", formatter.parseSeconds("01:35") == 95, tostring(formatter.parseSeconds("01:35")))
check("parseSeconds h:mm:ss", formatter.parseSeconds("1:02:03") == 3723)
check("parseSeconds 纯秒数", formatter.parseSeconds("95") == 95)
check("parseSeconds 空串返回 nil", formatter.parseSeconds("") == nil)
check("parseSeconds 0 返回 nil", formatter.parseSeconds("0:00") == nil)
check("parseSeconds 非法文本返回 nil", formatter.parseSeconds("abc") == nil)
check("parseSeconds nil 返回 nil", formatter.parseSeconds(nil) == nil)

local standardPractice = { id = 1, standard = 1, accuracy = 100 }
local normalPractice = { id = 2 }
check("达标模式阈值 100", homeworkService.passThreshold(standardPractice) == 100)
check("普通模式阈值 80", homeworkService.passThreshold(normalPractice) == 80)
check("达标模式 100% 视为完成",
  homeworkService.isCompleted(standardPractice, { is_answered = 1, accuracy = 100 }) == true)
check("达标模式 99% 不算完成",
  homeworkService.isCompleted(standardPractice, { is_answered = 1, accuracy = 99 }) == false)
check("普通模式 80% 视为完成",
  homeworkService.isCompleted(normalPractice, { is_answered = 1, accuracy = 80 }) == true)
check("普通模式 79% 不算完成",
  homeworkService.isCompleted(normalPractice, { is_answered = 1, accuracy = 79 }) == false)
check("未作答不算完成",
  homeworkService.isCompleted(normalPractice, { is_answered = 0, accuracy = 100 }) == false)
check("缺少 self 不算完成", homeworkService.isCompleted(normalPractice, nil) == false)

check("语音练习：单词跟读",
  homeworkService.isVoicePractice(practice("1", "练习", "单词跟读")) == true)
check("语音练习：朗读课文",
  homeworkService.isVoicePractice(practice("1", "练习", "朗读课文")) == true)
check("非语音：阅读理解",
  homeworkService.isVoicePractice(practice("1", "练习", "阅读理解")) == false)
check("非语音：判断题",
  homeworkService.isVoicePractice(practice("1", "练习", "判断题")) == false)

-- 参考耗时 = 第 1 名耗时 + 随机 2~4 秒
local rankFixture = {
  { spend_time = "1:00", account = { nickname = "第一名" } },
  { spend_time = "0:30", account = { nickname = "第二名" } },
  { spend_time = "2:10", account = { nickname = "第三名" } },
}
local jitterOk = true
local jitterSeen = {}
local lastSeconds = nil
for _ = 1, 200 do
  local value, ref = homeworkService.referenceSeconds(rankFixture)
  lastSeconds = value
  if type(ref) ~= "table" then
    jitterOk = false
  else
    if ref.nickname ~= "第一名" or ref.base ~= 60 then jitterOk = false end
    if ref.jitter < 2 or ref.jitter > 4 then jitterOk = false end
    jitterSeen[ref.jitter] = true
  end
  if value == nil or value < 62 or value > 64 then jitterOk = false end
end
check("参考耗时取第 1 名 + 随机 2~4 秒", jitterOk, tostring(lastSeconds))
local jitterVariety = 0
for _ in pairs(jitterSeen) do jitterVariety = jitterVariety + 1 end
check("随机偏移覆盖 2~4 秒区间", jitterVariety >= 2, "覆盖 " .. jitterVariety .. " 档")

local fixedSeconds, fixedRef = homeworkService.referenceSeconds(rankFixture, 3)
check("可注入固定偏移用于复现", fixedSeconds == 63, tostring(fixedSeconds))
check("参考来源字段完整（昵称/原始耗时/偏移）",
  fixedRef.nickname == "第一名" and fixedRef.base == 60 and fixedRef.jitter == 3)

local singleSeconds = homeworkService.referenceSeconds({
  { spend_time = "1:00", account = { nickname = "唯一" } },
}, 2)
check("只有 1 条记录时仍可取参考值", singleSeconds == 62, tostring(singleSeconds))

local emptySeconds, emptyReason = homeworkService.referenceSeconds({})
check("空排行榜没有参考值", emptySeconds == nil, tostring(emptyReason))
check("缺失原因可读", type(emptyReason) == "string" and emptyReason ~= "")

local badSeconds, badReason = homeworkService.referenceSeconds({
  { spend_time = nil },
})
check("榜首耗时缺失时没有参考值", badSeconds == nil, tostring(badReason))

local hugeSeconds, hugeReason = homeworkService.referenceSeconds({
  { spend_time = "25:00:00" },
})
check("超出 86400 秒的耗时被拒绝", hugeSeconds == nil, tostring(hugeReason))

-- 提交耗时校验：realSubmitCompletion 已在桩替换前保存，
-- 参数非法时会在发出请求之前直接回调失败，因此本项不发任何网络请求。
local rejectedZero, rejectedHuge = nil, nil
realSubmitCompletion({ seconds = 0, gameId = 1, homeworkId = "x", testbankId = "y" },
  function(ok) rejectedZero = (ok == false) end)
realSubmitCompletion({ seconds = 86401, gameId = 1, homeworkId = "x", testbankId = "y" },
  function(ok) rejectedHuge = (ok == false) end)
check("耗时 0 秒被拒绝", rejectedZero == true, tostring(rejectedZero))
check("耗时超过 86400 秒被拒绝", rejectedHuge == true, tostring(rejectedHuge))

-- ===== B/C. 异步场景 =====
local steps = {}

local function step(fn) steps[#steps + 1] = fn end

local batchPageModule = require "app.ui.pages.homework_batch"

-- B1 正常流程
step(function(next)
  log("")
  log("=== B1. 批量引擎：正常流程 ===")
  resetStubs()

  detailData["hw1"] = {
    id = "hw1",
    name = "作业一",
    testbanks = {
      practice("1001", "跟读练习", "单词跟读"),
      practice("1002", "判断题", "判断题"),
      practice("1003", "单选题", "单选题"),
      practice("1004", "填空题", "填空题", { standard = 1, accuracy = 100 }),
      practice("1005", "排序题", "排序题"),
      practice("1006", "听力题", "听力题"),
    },
  }
  detailData["hw2"] = {
    id = "hw2",
    name = "作业二",
    testbanks = {
      practice("2003", "单选题", "单选题"),
      practice("2004", "朗读课文", "朗读"),
    },
  }

  rankBehavior["hw1:1002"] = rank({ is_answered = 1, accuracy = 90 }, {})
  rankBehavior["hw1:1003"] = rank({ is_answered = 0, accuracy = 0 }, {
    { spend_time = "1:20", account = { nickname = "同学A" } },
    { spend_time = "1:35", account = { nickname = "同学B" } },
    { spend_time = "2:00", account = { nickname = "同学C" } },
  })
  rankBehavior["hw1:1004"] = rank({ is_answered = 1, accuracy = 100 }, {})
  -- 1005 无人完成：排行榜为空，没有可用参考耗时
  rankBehavior["hw1:1005"] = rank({ is_answered = 0, accuracy = 0 }, {})
  rankBehavior["hw1:1006"] = rank({ is_answered = 0, accuracy = 0 }, {
    { spend_time = "1:00", account = { nickname = "同学A" } },
    { spend_time = "1:30", account = { nickname = "同学B" } },
  })
  rankBehavior["hw2:2003"] = rank({ is_answered = 0, accuracy = 0 }, {
    { spend_time = "1:50", account = { nickname = "同学D" } },
    { spend_time = "2:00", account = { nickname = "同学E" } },
  })
  submitBehavior["hw1:1006"] = { ok = false, message = "服务端拒绝提交" }

  local batch = batchService.create({
    homeworks = { { id = "hw1", name = "作业一" }, { id = "hw2", name = "作业二" } },
    start = false,
  })
  batch.start()

  waitFor(function() return batch.finished end, function(done)
    check("批量任务执行完成", done == true)
    local stats = batch.stats
    check("作业总数 2", stats.homeworkCount == 2, tostring(stats.homeworkCount))
    check("练习总数 8", stats.practiceCount == 8, tostring(stats.practiceCount))
    check("待处理队列 6（排除 2 个语音练习）", stats.queueCount == 6, tostring(stats.queueCount))
    check("语音跳过 2", stats.skippedVoice == 2, tostring(stats.skippedVoice))
    check("已完成跳过 2", stats.skippedCompleted == 2, tostring(stats.skippedCompleted))
    check("无有效耗时 1", stats.noReference == 1, tostring(stats.noReference))
    check("提交成功 2", stats.success == 2, tostring(stats.success))
    check("提交失败 1", stats.failed == 1, tostring(stats.failed))
    check("语音练习没有发起排行榜请求", rankCalls["hw1:1001"] == nil and rankCalls["hw2:2004"] == nil)
    local submitted1003 = submitSeconds["hw1:1003"]
    check("提交耗时 = 第 1 名 80 秒 + 随机 2~4 秒",
      submitted1003 ~= nil and submitted1003 >= 82 and submitted1003 <= 84,
      tostring(submitted1003))
    local reference1003 = nil
    for _, entry in ipairs(batch.results) do
      if entry.testbankId == "1003" then reference1003 = entry.reference end
    end
    check("结果记录参考第 1 名与偏移",
      type(reference1003) == "table" and reference1003.base == 80
        and reference1003.jitter >= 2 and reference1003.jitter <= 4,
      reference1003 and string.format("base=%s jitter=%s", tostring(reference1003.base),
        tostring(reference1003.jitter)) or "无记录")
    check("作业之间的随机等待已执行", batch.gapSeconds >= 3 and batch.gapSeconds <= 6,
      tostring(batch.gapSeconds))
    check("没有排行榜记录时不提交", submitCalls["hw1:1005"] == nil,
      tostring(submitCalls["hw1:1005"]))
    check("同名练习按真实 ID 分别提交", submitCalls["hw1:1003"] == 1 and submitCalls["hw2:2003"] == 1,
      string.format("hw1:1003=%s hw2:2003=%s", tostring(submitCalls["hw1:1003"]),
        tostring(submitCalls["hw2:2003"])))
    check("没有重复提交", (submitCalls["hw1:1003"] or 0) == 1 and (submitCalls["hw1:1006"] or 0) == 1)

    local failedEntry = nil
    for _, entry in ipairs(batch.results) do
      if entry.status == "failed" then failedEntry = entry end
    end
    check("失败项保存了原因", failedEntry ~= nil and tostring(failedEntry.reason):find("拒绝提交", 1, true) ~= nil,
      failedEntry and failedEntry.reason or "无失败记录")
    next()
  end, 20000)
end)

-- B2 排行榜瞬时错误重试
step(function(next)
  log("")
  log("=== B2. 排行榜超时后重试 ===")
  resetStubs()
  detailData["hw3"] = {
    id = "hw3",
    name = "作业三",
    testbanks = { practice("3001", "单选题", "单选题") },
  }
  rankBehavior["hw3:3001"] = rank({ is_answered = 0, accuracy = 0 }, {
    { spend_time = "1:00", account = { nickname = "同学A" } },
    { spend_time = "1:40", account = { nickname = "同学B" } },
  }, { failKind = "timeout", failTimes = 1 })

  local batch = batchService.create({ homeworks = { { id = "hw3", name = "作业三" } } })
  waitFor(function() return batch.finished end, function(done)
    check("重试后任务完成", done == true)
    check("排行榜请求被重试一次", rankCalls["hw3:3001"] == 2, tostring(rankCalls["hw3:3001"]))
    check("重试成功后提交成功", batch.stats.success == 1, tostring(batch.stats.success))
    check("重试成功不计入无有效耗时", batch.stats.noReference == 0, tostring(batch.stats.noReference))
    next()
  end, 8000)
end)

-- B3 排行榜彻底失败
step(function(next)
  log("")
  log("=== B3. 排行榜持续失败 ===")
  resetStubs()
  detailData["hw4"] = {
    id = "hw4",
    name = "作业四",
    testbanks = { practice("4001", "单选题", "单选题") },
  }
  rankBehavior["hw4:4001"] = rank(nil, {}, { failKind = "timeout", failTimes = 5 })

  local batch = batchService.create({ homeworks = { { id = "hw4", name = "作业四" } } })
  waitFor(function() return batch.finished end, function(done)
    check("持续失败后任务仍正常结束", done == true)
    check("记为无有效排行榜数据", batch.stats.noReference == 1, tostring(batch.stats.noReference))
    check("不产生提交或失败计数", batch.stats.success == 0 and batch.stats.failed == 0)
    check("失败原因已记录", (batch.results[1] or {}).reason ~= nil,
      tostring((batch.results[1] or {}).reason))
    next()
  end, 8000)
end)

-- B4 提交超时后复核服务端状态
step(function(next)
  log("")
  log("=== B4. 提交超时后复核服务端状态 ===")
  resetStubs()
  detailData["hw5"] = {
    id = "hw5",
    name = "作业五",
    testbanks = { practice("5001", "单选题", "单选题") },
  }
  rankBehavior["hw5:5001"] = rank(nil, {}, {
    sequence = {
      { selfInfo = { is_answered = 0, accuracy = 0 }, list = {
        { spend_time = "1:00", account = { nickname = "同学A" } },
        { spend_time = "1:30", account = { nickname = "同学B" } },
      } },
      { selfInfo = { is_answered = 1, accuracy = 95 }, list = {
        { spend_time = "1:00", account = { nickname = "同学A" } },
        { spend_time = "1:30", account = { nickname = "同学B" } },
      } },
    },
  })
  submitBehavior["hw5:5001"] = { ok = false, message = "请求超时，请稍后重试", kind = "timeout" }

  local batch = batchService.create({ homeworks = { { id = "hw5", name = "作业五" } } })
  waitFor(function() return batch.finished end, function(done)
    check("超时后复核：任务完成", done == true)
    check("复核为已完成时按成功计", batch.stats.success == 1, tostring(batch.stats.success))
    check("未记为提交失败", batch.stats.failed == 0, tostring(batch.stats.failed))
    local entry = batch.results[1] or {}
    check("结果注明服务端已完成", tostring(entry.reason):find("服务端已完成", 1, true) ~= nil,
      tostring(entry.reason))
    next()
  end, 8000)
end)

-- B5 取消任务
step(function(next)
  log("")
  log("=== B5. 取消任务 ===")
  resetStubs()
  local testbanks = {}
  for index = 1, 6 do
    testbanks[index] = practice("600" .. index, "练习" .. index, "单选题")
    rankBehavior["hw6:600" .. index] = rank({ is_answered = 0, accuracy = 0 }, {
      { spend_time = "1:00", account = { nickname = "同学A" } },
      { spend_time = "1:30", account = { nickname = "同学B" } },
    })
    submitBehavior["hw6:600" .. index] = { delayMs = 120 }
  end
  detailData["hw6"] = { id = "hw6", name = "作业六", testbanks = testbanks }

  local batch = batchService.create({ homeworks = { { id = "hw6", name = "作业六" } } })
  waitFor(function() return batch.stats.success >= 1 end, function()
    batch.cancel()
    waitFor(function() return batch.finished end, function(done)
      check("取消后任务结束", done == true)
      check("阶段标记为已取消", batch.phase == "cancelled", tostring(batch.phase))
      check("未执行的队列项被标记取消", batch.stats.cancelled > 0, tostring(batch.stats.cancelled))
      local cancelledNoFail = true
      for _, entry in ipairs(batch.results) do
        if entry.status == "failed" then cancelledNoFail = false end
      end
      check("取消不会把已发出的请求记为失败", cancelledNoFail)
      next()
    end, 8000)
  end, 8000)
end)

-- B6 作业间隔等待期间可取消
step(function(next)
  log("")
  log("=== B6. 作业间隔等待期间取消 ===")
  resetStubs()
  detailData["hw7"] = {
    id = "hw7",
    name = "作业七",
    testbanks = { practice("7001", "单选题", "单选题") },
  }
  detailData["hw8"] = {
    id = "hw8",
    name = "作业八",
    testbanks = { practice("8001", "判断题", "判断题") },
  }
  for _, key in ipairs({ "hw7:7001", "hw8:8001" }) do
    rankBehavior[key] = rank({ is_answered = 0, accuracy = 0 }, {
      { spend_time = "1:00", account = { nickname = "同学A" } },
    })
  end

  local batch = batchService.create({
    homeworks = { { id = "hw7", name = "作业七" }, { id = "hw8", name = "作业八" } },
  })
  waitFor(function() return batch.phase == "gap" end, function(reached)
    check("第一份作业完成后进入等待阶段", reached == true, tostring(batch.phase))
    batch.cancel()
    waitFor(function() return batch.finished end, function(done)
      check("等待期间取消后任务结束", done == true)
      check("第二份作业没有提交", submitCalls["hw8:8001"] == nil,
        tostring(submitCalls["hw8:8001"]))
      check("取消项已计入统计", batch.stats.cancelled >= 1, tostring(batch.stats.cancelled))
      next()
    end, 10000)
  end, 15000)
end)

-- C1 作业首页多选上限
step(function(next)
  log("")
  log("=== C1. 作业首页多选（30 上限 / 全选 / 清空） ===")
  local listItems = {}
  for index = 1, 35 do
    listItems[index] = {
      id = "homework_" .. index,
      name = "作业 " .. index,
      testbank_count = 2,
      completion_rate = 0,
      vanclass_name = "测试班",
    }
  end
  homeworkService.fetchList = function(opts, callback)
    callback(true, { list = listItems, total = 35, page = 1, hasMore = false })
    return nil
  end

  local homeworkPage = require("app.ui.pages.homework").create()
  homeworkPage.load(true)

  waitFor(function() return homeworkPage.loaded and not homeworkPage.loading end, function(done)
    check("作业列表加载 35 条", #homeworkPage.list == 35, tostring(#homeworkPage.list))

    homeworkPage.toggleSelectionMode(true)
    check("进入多选模式", homeworkPage.selection.active == true)

    homeworkPage.selectAll()
    check("全选上限为 30", #homeworkPage.selection.items == 30,
      tostring(#homeworkPage.selection.items))

    homeworkPage.toggleSelect(homeworkPage.list[35])
    check("选满后继续选择被拒绝", #homeworkPage.selection.items == config.HOMEWORK_BATCH_MAX,
      tostring(#homeworkPage.selection.items))

    homeworkPage.clearSelection()
    check("清空选择", #homeworkPage.selection.items == 0)

    homeworkPage.toggleSelect(homeworkPage.list[1])
    check("单张卡片可选中", #homeworkPage.selection.items == 1)
    homeworkPage.toggleSelectionMode(false)
    check("退出多选清空选择", #homeworkPage.selection.items == 0
      and homeworkPage.selection.active == false)
    next()
  end, 6000)
end)

-- C2 批量操作页
step(function(next)
  log("")
  log("=== C2. 批量操作页进度与结果 ===")
  resetStubs()
  detailData["hw7"] = {
    id = "hw7",
    name = "作业七",
    testbanks = {
      practice("7001", "单选题", "单选题"),
      practice("7002", "朗读课文", "朗读"),
      practice("7003", "判断题", "判断题"),
    },
  }
  rankBehavior["hw7:7001"] = rank({ is_answered = 0, accuracy = 0 }, {
    { spend_time = "1:00", account = { nickname = "同学A" } },
    { spend_time = "1:45", account = { nickname = "同学B" } },
  })
  rankBehavior["hw7:7003"] = rank({ is_answered = 1, accuracy = 88 }, {})

  local finishedBatch = nil
  local page = batchPageModule.create({
    title = "测试批量",
    homeworks = { { id = "hw7", name = "作业七" } },
    onFinished = function(batch) finishedBatch = batch end,
  })

  waitFor(function() return finishedBatch ~= nil end, function(done)
    check("批量页任务回调触发", done == true)
    check("批量页统计：成功 1", page.batch.stats.success == 1, tostring(page.batch.stats.success))
    check("批量页统计：语音跳过 1", page.batch.stats.skippedVoice == 1)
    check("批量页统计：已完成跳过 1", page.batch.stats.skippedCompleted == 1)

    local texts = {}
    local function walk(view, depth)
      if view == nil or depth > 40 then return end
      pcall(function()
        local value = view.getText()
        if value ~= nil then texts[#texts + 1] = tostring(value) end
      end)
      local count = 0
      pcall(function() count = view.getChildCount() end)
      for index = 0, count - 1 do
        local child = nil
        pcall(function() child = view.getChildAt(index) end)
        walk(child, depth + 1)
      end
    end
    walk(page.view, 0)
    local joined = table.concat(texts, "\n")

    check("页面显示任务完成摘要", joined:find("任务完成", 1, true) ~= nil)
    check("页面显示成功计数", joined:find("成功", 1, true) ~= nil)
    check("页面显示语音跳过", joined:find("语音跳过", 1, true) ~= nil)
    check("页面显示结果条目", joined:find("单选题", 1, true) ~= nil)
    next()
  end, 8000)
end)

-- C3 作业详情一键完成入口
step(function(next)
  log("")
  log("=== C3. 作业详情「一键完成」入口 ===")
  resetStubs()
  detailData["hw8"] = {
    id = "hw8",
    name = "作业八",
    teacher_name = "老师",
    vanclass = { name = "测试班" },
    ["type"] = { name = "普通模式" },
    testbanks = {
      practice("8001", "单选题", "单选题"),
      practice("8002", "朗读课文", "朗读"),
    },
  }

  local detailPage = require("app.ui.pages.homework_detail").create({ id = "hw8", name = "作业八" })
  detailPage.load()

  waitFor(function() return detailPage.detail ~= nil end, function(done)
    check("作业详情加载完成", done == true)
    local texts = {}
    local function walk(view, depth)
      if view == nil or depth > 40 then return end
      pcall(function()
        local value = view.getText()
        if value ~= nil then texts[#texts + 1] = tostring(value) end
      end)
      local count = 0
      pcall(function() count = view.getChildCount() end)
      for index = 0, count - 1 do
        local child = nil
        pcall(function() child = view.getChildAt(index) end)
        walk(child, depth + 1)
      end
    end
    walk(detailPage.view, 0)
    local joined = table.concat(texts, "\n")
    check("详情页存在「一键完成」按钮", joined:find("一键完成", 1, true) ~= nil)
    check("详情页说明使用排行榜第 1 名耗时", joined:find("第 1 名", 1, true) ~= nil)
    check("详情页不再声称不会代替用户操作",
      joined:find("不会代替你答题", 1, true) == nil)
    next()
  end, 6000)
end)

-- C4 关于页文案
step(function(next)
  log("")
  log("=== C4. 关于页项目来源与致谢 ===")
  local about = require("app.ui.pages.about").create()
  local texts = {}
  local function walk(view, depth)
    if view == nil or depth > 40 then return end
    pcall(function()
      local value = view.getText()
      if value ~= nil then texts[#texts + 1] = tostring(value) end
    end)
    local count = 0
    pcall(function() count = view.getChildCount() end)
    for index = 0, count - 1 do
      local child = nil
      pcall(function() child = view.getChildAt(index) end)
      walk(child, depth + 1)
    end
  end
  walk(about.view, 0)
  local joined = table.concat(texts, "\n")

  check("关于页含项目来源章节", joined:find("项目来源", 1, true) ~= nil)
  check("关于页提及 VanthinkWebMDUI2", joined:find("VanthinkWebMDUI2", 1, true) ~= nil)
  check("关于页说明 MDUI2 早期实现", joined:find("MDUI2", 1, true) ~= nil)
  check("关于页说明原生重构", joined:find("原生重构", 1, true) ~= nil)
  check("关于页致谢 NeLuaJ+ / AndroidX / Material",
    joined:find("NeLuaJ+、AndroidX、Material Components for Android", 1, true) ~= nil)
  check("关于页未把 Web 版描述为第三方贡献者",
    joined:find("第三方贡献", 1, true) == nil)
  check("关于页未声明许可证", joined:find("MIT", 1, true) == nil
    and joined:find("Apache License", 1, true) == nil)
  next()
end)

-- ===== 执行 =====
local index = 0

local function finish()
  log("")
  log(string.format("=== 汇总：PASS %d / FAIL %d ===", passCount, failCount))
  log(failCount == 0 and "结论：v0.2.4 批量操作检查全部通过" or "结论：存在失败项，请查看上方 FAIL 明细")
  flush()
  print(string.format("test_batch_v024 完成：PASS %d / FAIL %d -> %s", passCount, failCount, OUT))
end

local function runNext()
  index = index + 1
  local current = steps[index]
  if current == nil then
    finish()
    return
  end
  local ok, err = pcall(current, function()
    activity.delay(120, runNext)
  end)
  if not ok then
    fail("步骤异常 #" .. index, tostring(err))
    activity.delay(120, runNext)
  end
end

log("VanthinkMD3 v0.2.4 批量操作测试")
log("版本常量：" .. tostring(config.APP_VERSION))
flush()
runNext()
