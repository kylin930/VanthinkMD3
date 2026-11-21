-- 练习操作：排行榜与「记录练习完成」。
-- 作业级别的自动操作由 app/services/homework_batch.lua 统一执行
-- （详情页「一键完成」、作业首页「批量操作」两个入口）；
-- 本文件只处理单个练习的手动入口：
--   * 「记录练习完成」由用户填写实际耗时并二次确认，用于确实完成过的情况；
--   * 不生成随机耗时、不修改准确率与成绩。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local formatter = require "app.utils.formatter"
local homeworkService = require "app.services.homework"

local M = {}

local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")

local function rankItem(index, participant, colors)
  local account = participant.account or {}
  local nickname = account.nickname or "同学"
  local rankColor = colors.onSurface
  if index == 1 then rankColor = colors.primary end
  return kit.row({
    kit.column({
      kit.text(tostring(index), {
        size = kit.TYPOGRAPHY.title,
        color = rankColor,
        bold = true,
      }),
    }, { width = "32dp" }),
    kit.column({
      kit.text(nickname, {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurface,
        maxLines = 1,
      }),
      kit.text(string.format("正确率 %s · 耗时 %s", formatter.percent(participant.accuracy),
        tostring(participant.spend_time or "-")), {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
      }),
    }, { width = "0dp", weight = 1 }),
  }, { width = "match", paddingTop = 10, paddingBottom = 10 })
end

-- 排行榜弹窗
function M.showRankList(homeworkId, testbankId)
  local colors = theme.colors()
  local content = kit.column({
    kit.row({
      kit.spinner(20),
      kit.text("正在获取排行榜…", {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
        marginStart = 10,
      }),
    }, { width = "match", padding = 8 }),
  }, { width = "match", padding = 8 })

  local dialog = dialogs.custom({
    title = "练习排行榜",
    view = content,
    negativeLabel = "关闭",
  })

  homeworkService.fetchRankList(homeworkId, testbankId, function(ok, data)
    local holder = kit.column({}, { width = "match" })
    if not ok then
      holder.addView(kit.stateView({
        icon = "cloud_off",
        title = "排行榜加载失败",
        message = tostring(data),
      }))
    elseif #data.list == 0 then
      holder.addView(kit.stateView({
        icon = "leaderboard",
        title = "还没有同学完成",
        message = "完成练习后就能出现在排行榜里",
      }))
    else
      local selfInfo = data["self"]
      if type(selfInfo) == "table" and selfInfo.is_answered ~= nil then
        local answered = selfInfo.is_answered == 1 or selfInfo.is_answered == "1"
          or selfInfo.is_answered == true
        holder.addView(kit.card({
          kit.text(answered and "你已完成本次练习" or "你还没有完成本次练习", {
            size = kit.TYPOGRAPHY.label,
            color = colors.onSurfaceVariant,
          }),
        }, { padding = 12, marginBottom = 8 }))
      end
      for index, participant in ipairs(data.list) do
        holder.addView(rankItem(index, participant, colors))
      end
    end
    content.removeAllViews()
    content.addView(holder)
  end)

  return dialog
end

-- 记录练习完成：用户输入真实耗时后提交
function M.recordCompletion(homework, practice, onDone)
  local colors = theme.colors()
  local game = practice.game or {}
  local gameName = tostring(game.name or "练习")
  local standardMode = homeworkService.isStandardMode(practice)

  local secondsInput = kit.textInput({
    hint = "实际练习耗时（秒）",
    inputType = "number",
    textSize = 16,
  })

  local requirement = "普通模式练习"
  if standardMode then
    requirement = string.format("达标要求：%s 分 / 正确率 %s",
      formatter.percent((tonumber(practice.standard) or 0) * 100),
      tostring(practice.accuracy or "-"))
  end

  local content = kit.column({
    kit.text(string.format("%s · %s", gameName, tostring(practice.name or "")), {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      bold = true,
    }),
    kit.spacer(6),
    kit.text(requirement, {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }),
    kit.spacer(14),
    secondsInput.root,
    kit.spacer(12),
    kit.text(
      "说明：本操作会把「已完成」记录提交到服务器，只能用于你确实完成过本次练习的情况。"
      .. "应用不会代刷成绩、不会随机生成耗时，也不会修改准确率。",
      { size = kit.TYPOGRAPHY.label, color = colors.outline, maxLines = 6 }),
  }, { width = "match", padding = 8 })

  local submitting = false
  dialogs.custom({
    title = "记录练习完成",
    view = content,
    positiveLabel = "确认提交",
    negativeLabel = "取消",
    onPositive = function(dialog)
      if submitting then return end
      local seconds = tonumber(secondsInput.getText())
      if seconds == nil or seconds <= 0 or seconds > 24 * 3600 then
        dialogs.snackbar("请输入 1 ~ 86400 之间的实际耗时（秒）")
        return
      end
      submitting = true
      pcall(function() dialog.dismiss() end)
      local progress = dialogs.progress("正在提交完成记录…")
      homeworkService.submitCompletion({
        gameId = game.id,
        homeworkId = homework.id,
        testbankId = practice.id,
        seconds = math.floor(seconds),
      }, function(ok, message)
        dialogs.dismiss(progress)
        submitting = false
        if onDone then onDone(ok, message) end
      end)
    end,
  })
end

-- 练习项操作面板
function M.showPracticeActions(homework, practice, onChanged)
  local voice = homeworkService.isVoicePractice(practice)
  local items = {
    { label = "查看排行榜", value = "rank" },
  }
  if voice then
    items[#items + 1] = { label = "语音练习（本版本不支持在应用内完成）", value = "voice" }
  else
    items[#items + 1] = { label = "记录练习完成（需真实完成）", value = "record" }
  end
  items[#items + 1] = { label = "取消", value = "cancel" }

  dialogs.list({
    title = string.format("%s · %s",
      tostring(practice.game and practice.game.name or "练习"),
      tostring(practice.name or "")),
    items = items,
    onSelect = function(item)
      if item.value == "rank" then
        M.showRankList(homework.id, practice.id)
      elseif item.value == "record" then
        M.recordCompletion(homework, practice, function(ok, message)
          if ok then
            dialogs.snackbar("已完成记录提交")
            if onChanged then onChanged() end
          else
            dialogs.alert("提交失败", message)
          end
        end)
      elseif item.value == "voice" then
        dialogs.alert("暂不支持",
          "语音练习需要录音上传与语音评测服务，本版本未集成；请在网页端完成。"
          .. "详见下方“语音练习未实现说明”。")
      end
    end,
  })
end

return M
