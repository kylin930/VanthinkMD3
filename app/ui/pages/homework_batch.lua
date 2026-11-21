-- 批量操作页：作业「一键完成」与多选「批量操作」共用的执行界面。
-- 显示统计概览、实时进度、执行计数与逐项结果；不提供耗时输入或逐项确认。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local formatter = require "app.utils.formatter"
local batchService = require "app.services.homework_batch"

local M = {}

local function statusStyle(status, colors)
  if status == "success" then
    return {
      background = colors.tertiaryContainer,
      color = colors.onTertiaryContainer,
    }
  elseif status == "failed" then
    return {
      background = colors.errorContainer,
      color = colors.onErrorContainer,
    }
  elseif status == "noReference" then
    return {
      background = colors.secondaryContainer,
      color = colors.onSecondaryContainer,
    }
  end
  return {
    background = colors.surfaceContainerHighest,
    color = colors.onSurfaceVariant,
  }
end

-- 数字 + 标题的小统计块，返回视图与数值文本控件
local function statBlock(label, colors, colorRole)
  local value = kit.text("0", {
    size = kit.TYPOGRAPHY.headline,
    color = colorRole or colors.primary,
    bold = true,
  })
  local view = kit.column({
    value,
    kit.text(label, { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
  }, { width = "0dp", weight = 1 })
  return view, value
end

local function setProgress(view, percent)
  if view == nil then return end
  local value = math.max(0, math.min(100, math.floor(percent + 0.5)))
  local ok = pcall(function() view.setProgressCompat(value, true) end)
  if not ok then pcall(function() view.setProgress(value) end) end
end

function M.create(opts)
  local o = opts or {}
  local colors = theme.colors()
  local shell = kit.scrollPage({})

  local page = {
    key = "homework_batch",
    batch = nil,
    finished = false,
  }

  local sub = router.subPage({
    title = o.title or "批量操作",
    content = shell.root,
    onBack = function()
      if page.batch ~= nil and page.batch.running then
        dialogs.confirm({
          title = "任务正在执行",
          message = "返回会取消尚未执行的队列项目，已经提交的项目不会回退。确定返回？",
          positiveLabel = "返回并取消",
          onConfirm = function()
            page.batch.cancel()
            router.back()
          end,
        })
        return
      end
      router.back()
    end,
  })
  page.view = sub.root

  -- ===== 概览 =====
  local overviewHomeworks, overviewHomeworksValue = statBlock("作业总数", colors)
  local overviewPractices, overviewPracticesValue = statBlock("练习总数", colors, colors.tertiary)
  local overviewPending, overviewPendingValue = statBlock("待处理", colors)
  local overviewDone, overviewDoneValue = statBlock("已完成跳过", colors, colors.tertiary)

  shell.add(kit.spacer(8))
  shell.add(kit.card({
    kit.text("任务概览", { size = kit.TYPOGRAPHY.title, color = colors.onSurface, bold = true }),
    kit.spacer(12),
    kit.row({
      overviewHomeworks,
      overviewPractices,
      overviewPending,
      overviewDone,
    }, { width = "match" }),
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

  -- ===== 执行状态 =====
  local stateText = kit.text("准备中…", {
    size = kit.TYPOGRAPHY.body,
    color = colors.onSurface,
    maxLines = 2,
  })
  local progressCaption = kit.text("0 / 0", {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
  })
  local progressBar = kit.linearProgress(false)
  setProgress(progressBar, 0)

  local counterSuccess, counterSuccessValue = statBlock("成功", colors, colors.tertiary)
  local counterFailed, counterFailedValue = statBlock("失败", colors, colors.error)
  local counterVoice, counterVoiceValue = statBlock("语音跳过", colors, colors.secondary)
  local counterNoRef, counterNoRefValue = statBlock("无有效耗时", colors, colors.onSurfaceVariant)
  local counterCompleted, counterCompletedValue = statBlock("已完成跳过", colors, colors.tertiary)

  shell.add(kit.card({
    stateText,
    kit.spacer(10),
    kit.row({
      progressCaption,
      kit.column({}, { width = "0dp", weight = 1 }),
    }, { width = "match" }),
    kit.spacer(6),
    progressBar,
    kit.spacer(14),
    kit.row({
      counterSuccess,
      counterFailed,
      counterVoice,
    }, { width = "match" }),
    kit.spacer(10),
    kit.row({
      counterNoRef,
      counterCompleted,
      kit.column({}, { width = "0dp", weight = 1 }),
    }, { width = "match" }),
  }, {
    marginHorizontal = kit.SPACING.pageHorizontal,
    marginTop = kit.SPACING.cardGap,
    padding = kit.SPACING.cardPadding,
  }))

  -- ===== 操作按钮 =====
  local cancelButton = kit.button("取消任务", {
    style = "outlined",
    height = "44dp",
    iconName = "close",
    onClick = function()
      if page.batch == nil or not page.batch.running then return end
      dialogs.confirm({
        title = "取消任务",
        message = "将停止尚未执行的队列项目；已经发出的请求会按其真实结果记录，不会被记为失败。",
        positiveLabel = "取消任务",
        negativeLabel = "继续执行",
        onConfirm = function()
          page.batch.cancel()
        end,
      })
    end,
  })
  local backButton = kit.button("返回", {
    height = "44dp",
    onClick = function()
      router.back()
    end,
  })
  backButton.setVisibility(8)

  shell.add(kit.row({
    cancelButton,
    kit.hSpacer(8),
    backButton,
    kit.column({}, { width = "0dp", weight = 1 }),
  }, {
    width = "match",
    paddingStart = kit.SPACING.pageHorizontal,
    paddingEnd = kit.SPACING.pageHorizontal,
    paddingTop = kit.SPACING.cardGap,
  }))

  -- ===== 结果列表 =====
  local resultsInner = kit.column({}, { width = "match" })
  local resultsCard = kit.card({
    kit.text("执行结果", { size = kit.TYPOGRAPHY.title, color = colors.onSurface, bold = true }),
    kit.spacer(8),
    resultsInner,
  }, {
    marginHorizontal = kit.SPACING.pageHorizontal,
    marginTop = kit.SPACING.cardGap,
    padding = kit.SPACING.cardPadding,
  })
  shell.add(resultsCard)
  shell.add(kit.spacer(24))

  local renderedResults = 0

  local function renderResult(entry)
    local label = batchService.LABEL[entry.status] or tostring(entry.status)
    local style = statusStyle(entry.status, colors)
    local details = { entry.homeworkName or "作业" }
    if entry.seconds ~= nil then
      local reference = entry.reference
      if type(reference) == "table" and reference.base ~= nil then
        details[#details + 1] = string.format("耗时 %s（第 1 名 %d 秒 + %d 秒）",
          formatter.duration(entry.seconds), reference.base, reference.jitter or 0)
      else
        details[#details + 1] = "耗时 " .. formatter.duration(entry.seconds)
      end
    end
    if entry.reason ~= nil and tostring(entry.reason) ~= "" then
      details[#details + 1] = tostring(entry.reason)
    end
    return kit.listItem({
      title = entry.practiceName or "练习",
      subtitle = table.concat(details, " · "),
      titleMaxLines = 2,
      subtitleMaxLines = 3,
      trailingView = kit.badge(label, style),
    })
  end

  local function appendResults(batch)
    if batch == nil then return end
    local results = batch.results or {}
    for index = renderedResults + 1, #results do
      if renderedResults > 0 then
        resultsInner.addView(kit.divider(2, 2))
      end
      resultsInner.addView(renderResult(results[index]))
    end
    renderedResults = #results
  end

  local function summaryText(batch)
    if batch.finished then
      if batch.phase == "cancelled" then
        return string.format("任务已取消：成功 %d，失败 %d，未执行 %d",
          batch.stats.success, batch.stats.failed, batch.stats.cancelled)
      end
      return string.format("任务完成：成功 %d，失败 %d，跳过 %d",
        batch.stats.success, batch.stats.failed,
        batch.stats.skippedVoice + batch.stats.skippedCompleted + batch.stats.noReference)
    end
    local current = batch.current
    if current == nil then
      return batch.phase == "detail" and "正在获取作业详情…" or "准备中…"
    end
    if current.stage == "detail" then
      return string.format("正在获取作业详情：%s（%d/%d）",
        tostring(current.homeworkName), batch.currentIndex, batch.currentTotal)
    end
    if current.stage == "gap" then
      return string.format("%s 已完成，等待 %d 秒后继续下一份作业",
        tostring(current.homeworkName), batch.gapSeconds or 0)
    end
    if current.stage == "submit" and current.reference ~= nil then
      return string.format("正在提交：%s · %s（第 1 名 %s %d 秒 + 随机 %d 秒 = %d 秒）",
        tostring(current.homeworkName), tostring(current.practiceName),
        tostring(current.reference.nickname), current.reference.base or 0,
        current.reference.jitter or 0, current.seconds)
    end
    return string.format("正在查询排行榜：%s · %s",
      tostring(current.homeworkName), tostring(current.practiceName))
  end

  local function update(batch)
    if batch == nil then return end
    page.batch = batch
    local stats = batch.stats

    overviewHomeworksValue.setText(tostring(stats.homeworkCount))
    overviewPracticesValue.setText(tostring(stats.practiceCount))
    overviewPendingValue.setText(tostring(stats.queueCount))
    overviewDoneValue.setText(tostring(stats.skippedCompleted))

    counterSuccessValue.setText(tostring(stats.success))
    counterFailedValue.setText(tostring(stats.failed))
    counterVoiceValue.setText(tostring(stats.skippedVoice))
    counterNoRefValue.setText(tostring(stats.noReference))
    counterCompletedValue.setText(tostring(stats.skippedCompleted))

    stateText.setText(summaryText(batch))

    local total = batch.currentTotal or 0
    local index = batch.currentIndex or 0
    if batch.finished then
      total = math.max(total, index)
      index = total
    end
    progressCaption.setText(string.format("%d / %d", index, total))
    if total > 0 then
      setProgress(progressBar, index / total * 100)
    elseif batch.finished then
      setProgress(progressBar, 100)
    end

    appendResults(batch)

    if batch.finished then
      page.finished = true
      cancelButton.setVisibility(8)
      backButton.setVisibility(0)
    end
  end

  local function startBatch()
    local homeworks = {}
    for _, item in ipairs(o.homeworks or {}) do
      if type(item) == "table" and item.id ~= nil then
        homeworks[#homeworks + 1] = { id = item.id, name = item.name }
      end
    end
    if #homeworks == 0 then
      stateText.setText("没有可执行的作业")
      cancelButton.setVisibility(8)
      backButton.setVisibility(0)
      return
    end

    page.batch = batchService.create({
      homeworks = homeworks,
      onUpdate = function(batch)
        update(batch)
      end,
      onDone = function(batch)
        update(batch)
        for _, error in ipairs(batch.errors or {}) do
          resultsInner.addView(kit.divider(2, 2))
          resultsInner.addView(kit.listItem({
            title = "作业详情获取失败",
            subtitle = string.format("%s · %s", tostring(error.homeworkName), tostring(error.reason)),
            titleMaxLines = 2,
            subtitleMaxLines = 3,
            trailingView = kit.badge("失败", statusStyle("failed", colors)),
          }))
        end
        if o.onFinished then pcall(o.onFinished, batch) end
        if batch.stats.success + batch.stats.failed + batch.stats.cancelled > 0
          or batch.finished then
          dialogs.snackbar(string.format("批量操作结束：成功 %d，失败 %d",
            batch.stats.success, batch.stats.failed))
        end
      end,
    })
  end

  update(nil)
  stateText.setText("准备中…")
  startBatch()

  function page.refresh()
    update(page.batch)
  end

  return page
end

return M
