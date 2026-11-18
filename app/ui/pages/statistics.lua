-- 统计中心：账号使用统计（摘要卡片 + 柱状图 + 折线图 + 时间范围筛选）。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local chart = require "app.ui.chart"
local state = require "app.state"
local statisticsService = require "app.services.statistics"
local formatter = require "app.utils.formatter"
local authService = require "app.services.auth"

local M = {}

local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")

local function metricCard(title, value, suffix, detail, accent, colors)
  return kit.card({
    kit.text(title, { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
    kit.spacer(8),
    kit.row({
      kit.text(value, {
        size = 24,
        color = accent or colors.primary,
        bold = true,
      }),
      kit.text(suffix or "", {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
        marginStart = 4,
      }),
    }, { width = "match" }),
    kit.spacer(4),
    kit.text(detail or "", {
      size = kit.TYPOGRAPHY.label,
      color = colors.outline,
      maxLines = 2,
    }),
  }, { width = "0dp", weight = 1, padding = 14, marginStart = 0, marginEnd = 0 })
end

function M.create()
  local colors = theme.colors()
  local now = formatter.nowParts()
  local page = {
    key = "statistics",
    year = now.year,
    month = now.month,
    loading = false,
    loaded = false,
    error = nil,
    data = nil,
  }

  local shell = kit.scrollPage({
    onRefresh = function() page.load() end,
  })
  page.view = shell.root

  local function monthPicker()
    local holder = kit.row({
      kit.iconButton("schedule", {
        onClick = function()
          dialogs.list({
            title = "选择统计月份",
            items = (function()
              local items = {}
              for month = 1, 12 do
                items[#items + 1] = { label = month .. " 月", value = month }
              end
              return items
            end)(),
            onSelect = function(item)
              page.month = item.value
              page.load()
            end,
          })
        end,
      }),
      kit.badge(string.format("%d 年 %d 月", page.year, page.month), {
        background = colors.secondaryContainer,
        color = colors.onSecondaryContainer,
      }),
      kit.spacer(6),
      kit.iconButton("refresh", { onClick = function() page.load() end }),
    }, { width = "wrap" })
    return holder
  end

  local function yearRow()
    local row = kit.row({
      kit.button(tostring(page.year) .. " 年", {
        style = "outlined",
        height = "36dp",
        size = kit.TYPOGRAPHY.label,
        onClick = function()
          local items = {}
          for offset = 0, 3 do
            local year = now.year - offset
            items[#items + 1] = { label = year .. " 年", value = year }
          end
          dialogs.list({
            title = "选择年份",
            items = items,
            onSelect = function(item)
              page.year = item.value
              page.load()
            end,
          })
        end,
      }),
      kit.spacer(8),
      monthPicker(),
    }, { width = "match", paddingStart = 20, paddingEnd = 16 })
    return row
  end

  function page.render()
    shell.clear()
    shell.add(kit.pageHeader("统计", "你的练习与学习数据", {
      kit.iconButton("refresh", { onClick = function() page.load() end }),
    }))
    shell.add(yearRow())

    if page.loading and page.data == nil then
      shell.add(kit.row({
        kit.spinner(24),
        kit.text("正在加载统计数据…", {
          size = kit.TYPOGRAPHY.body,
          color = colors.onSurfaceVariant,
          marginStart = 12,
        }),
      }, { width = "match", padding = 28, gravity = "center" }))
      return
    end

    if page.error ~= nil then
      shell.add(kit.stateView({
        icon = "cloud_off",
        title = "统计数据加载失败",
        message = page.error,
        actionLabel = "重试",
        actionIcon = "refresh",
        onAction = function() page.load(true) end,
      }))
      return
    end

    local data = page.data
    if data == nil then
      shell.add(kit.stateView({
        icon = "insights",
        title = "暂无统计数据",
        message = "完成练习后这里会显示你的学习记录",
      }))
      return
    end

    shell.add(kit.spacer(4))
    shell.add(kit.row({
      metricCard("总练习次数", formatter.int(data.practice.count), "次",
        string.format("月均 %s 次 · 本月 %s 次",
          formatter.number(data.practice.avg), formatter.int(data.practice.monthAvg)),
        colors.primary, colors),
      kit.spacer(12),
      metricCard("答对题数", formatter.number(data.exercise.count), "题",
        string.format("月均 %s 题 · 本月 %s 题",
          formatter.number(data.exercise.avg), formatter.int(data.exercise.monthAvg)),
        colors.tertiary, colors),
    }, { width = "match", paddingStart = 16, paddingEnd = 16 }))
    shell.add(kit.spacer(6))
    shell.add(kit.row({
      metricCard("练习天数", formatter.int(data.days.count), "天",
        string.format("日均 %s 分钟 · 本月日均 %s 分钟",
          formatter.number(data.days.avg), formatter.int(data.days.monthAvg)),
        colors.secondary, colors),
      kit.spacer(12),
      metricCard("拍照练习", formatter.int(data.photo.count), "次",
        string.format("月均 %s 次 · 本月 %s 次",
          formatter.number(data.photo.avg), formatter.int(data.photo.monthAvg)),
        colors.primary, colors),
    }, { width = "match", paddingStart = 16, paddingEnd = 16 }))

    shell.add(kit.sectionTitle("每日答对题数"))
    shell.add(kit.card({
      (function()
        local points = {}
        for _, item in ipairs(data.daily or {}) do
          points[#points + 1] = {
            label = formatter.shortDate(item.day),
            value = item.score,
          }
        end
        if #points == 0 then
          return kit.stateView({
            icon = "insights",
            title = "本月暂无每日数据",
            message = "换个月份看看，或先去完成一些练习",
          })
        end
        return chart.barChart({ points = points, heightDp = 190 })
      end)(),
    }, { marginHorizontal = 16, padding = 12 }))

    shell.add(kit.sectionTitle("每日练习时长（分钟）"))
    shell.add(kit.card({
      (function()
        local points = {}
        for _, item in ipairs(data.daily or {}) do
          points[#points + 1] = {
            label = formatter.shortDate(item.day),
            value = item.time,
          }
        end
        if #points == 0 then
          return kit.stateView({
            icon = "schedule",
            title = "本月暂无时长数据",
            message = "完成练习后会记录练习时长",
          })
        end
        return chart.lineChart({ points = points, heightDp = 190 })
      end)(),
    }, { marginHorizontal = 16, padding = 12 }))

    if data.pl.totalTime ~= nil and data.pl.totalTime > 0 then
      shell.add(kit.sectionTitle("磨耳朵"))
      shell.add(kit.card({
        kit.row({
          kit.column({
            kit.text("累计 " .. formatter.number(data.pl.totalTime), {
              size = kit.TYPOGRAPHY.title,
              color = colors.onSurface,
              bold = true,
            }),
            kit.text("分钟", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
          }, { width = "0dp", weight = 1 }),
          kit.column({
            kit.text("日均 " .. formatter.number(data.pl.avgTime), {
              size = kit.TYPOGRAPHY.title,
              color = colors.onSurface,
              bold = true,
            }),
            kit.text("分钟", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
          }, { width = "0dp", weight = 1 }),
        }, { width = "match" }),
        kit.spacer(6),
        kit.text("起始时间：" .. formatter.friendlyTime(data.pl.startTime), {
          size = kit.TYPOGRAPHY.label,
          color = colors.outline,
        }),
      }, { marginHorizontal = 16, padding = 16 }))
    end

    shell.add(kit.spacer(24))
  end

  function page.load(reloadAccount)
    if page.loading then return end
    page.loading = true
    page.error = nil
    if page.data == nil then page.render() end

    local function requestReport()
      statisticsService.fetchReport({ year = page.year, month = page.month },
        function(ok, dataOrMessage)
          page.loading = false
          shell.setRefreshing(false)
          if not ok then
            page.error = tostring(dataOrMessage)
            page.render()
            return
          end
          page.data = dataOrMessage
          page.loaded = true
          page.render()
        end)
    end

    if state.account == nil or reloadAccount then
      authService.fetchAccount(function(ok)
        if not ok then
          page.loading = false
          page.error = "账号信息加载失败，请重新登录"
          page.render()
          return
        end
        requestReport()
      end)
    else
      requestReport()
    end
  end

  function page.onShow()
    if not page.loaded then
      page.load(page.data == nil)
    else
      page.render()
    end
  end

  page.render()
  return page
end

return M
