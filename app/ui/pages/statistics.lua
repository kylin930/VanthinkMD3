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

-- 摘要卡片。half = true 表示双列布局中的一半宽度（0dp + weight = 1）；
-- half = false 用于窄屏单列，占满可用宽度。
-- 高度一律 wrap：父行高度是 wrap_content，子视图写 match_parent 在滚动容器里
-- 会被测量成 0 高。
local function metricCard(spec, half)
  local colors = spec.colors
  return kit.card({
    kit.text(spec.title, {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      maxLines = 1,
    }),
    kit.spacer(8),
    kit.row({
      -- 数值占用剩余宽度、单位固定宽度：数值再长也不会把「次 / 题 / 天」挤出卡片
      kit.text(spec.value, {
        size = 24,
        color = spec.accent or colors.primary,
        bold = true,
        width = "0dp",
        weight = 1,
        maxLines = 1,
      }),
      kit.text(spec.suffix or "", {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
        marginStart = 4,
        maxLines = 1,
      }),
    }, { width = "match" }),
    kit.spacer(4),
    kit.text(spec.detail or "", {
      size = kit.TYPOGRAPHY.label,
      color = colors.outline,
      maxLines = 3,
    }),
  }, {
    width = half and "0dp" or "match",
    height = "wrap",
    weight = half and 1 or nil,
    padding = kit.SPACING.cardPadding,
  })
end

-- 两组摘要卡片：宽屏双列（等分 + 固定 cardGap 间距），窄屏退化为单列。
-- 双列等分靠 weight，两列间距用 hSpacer（横向行里 kit.spacer 是 width=match，会把卡片挤没）。
local function metricPair(left, right)
  if kit.isCompactWidth() then
    return kit.column({
      metricCard(left, false),
      kit.spacer(kit.SPACING.cardGap),
      metricCard(right, false),
    }, {
      width = "match",
      paddingStart = kit.SPACING.pageHorizontal,
      paddingEnd = kit.SPACING.pageHorizontal,
    })
  end
  return kit.row({
    metricCard(left, true),
    kit.hSpacer(kit.SPACING.cardGap),
    metricCard(right, true),
  }, {
    width = "match",
    -- 顶部对齐：两张卡片内容行数不同时高度会不同，居中会显得错位
    gravity = "start|top",
    paddingStart = kit.SPACING.pageHorizontal,
    paddingEnd = kit.SPACING.pageHorizontal,
  })
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

  -- 月份选择：只保留「月份图标 + 当前年月徽标」。
  -- 刷新入口只保留页头那一个，这里不再放重复的刷新按钮。
  local function monthPicker()
    local badge = kit.badge(string.format("%d 年 %d 月", page.year, page.month), {
      background = colors.secondaryContainer,
      color = colors.onSecondaryContainer,
    })
    -- 徽标左间距用 applyMargins：横向行里的 kit.spacer 宽度是 match，会把内容挤出屏幕
    kit.applyMargins(badge, { start = 4 })
    return kit.row({
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
      badge,
    }, { width = "wrap" })
  end

  -- 年份选择按钮：48dp 稳定触控高度。
  -- 之前写成 36dp，MaterialButton 自带 insetTop/insetBottom（各 6dp），
  -- 可用内容高度只剩 24dp，中文 + 数字混排的行高（约 20~22dp）贴着上下内边距，
  -- 实机上表现为年份文字被裁切。48dp 后内容区 36dp，文字垂直居中且不再被裁。
  local function yearButton()
    return kit.button(tostring(page.year) .. " 年", {
      style = "outlined",
      height = "48dp",
      size = kit.TYPOGRAPHY.body,
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
    })
  end

  -- 年月筛选栏：整体水平居中，控件之间统一 8dp。
  -- 320dp 窄屏会拆成两行（仍居中），保证按钮与徽标都完整显示、不贴右边缘。
  local function yearRow()
    if kit.isCompactWidth() then
      return kit.column({
        kit.row({ yearButton() }, {
          width = "match", gravity = "center_horizontal", paddingTop = 4,
        }),
        kit.row({ monthPicker() }, {
          width = "match", gravity = "center_horizontal", paddingTop = 4,
        }),
      }, {
        width = "match",
        paddingStart = kit.SPACING.pageHorizontal,
        paddingEnd = kit.SPACING.pageHorizontal,
      })
    end
    return kit.row({
      yearButton(),
      kit.hSpacer(8),
      monthPicker(),
    }, {
      width = "match",
      gravity = "center_horizontal",
      paddingStart = kit.SPACING.pageHorizontal,
      paddingEnd = kit.SPACING.pageHorizontal,
    })
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

    shell.add(kit.spacer(8))
    shell.add(metricPair({
      title = "总练习次数",
      value = formatter.int(data.practice.count),
      suffix = "次",
      detail = string.format("月均 %s 次 · 本月 %s 次",
        formatter.number(data.practice.avg), formatter.int(data.practice.monthAvg)),
      accent = colors.primary,
      colors = colors,
    }, {
      title = "答对题数",
      value = formatter.number(data.exercise.count),
      suffix = "题",
      detail = string.format("月均 %s 题 · 本月 %s 题",
        formatter.number(data.exercise.avg), formatter.int(data.exercise.monthAvg)),
      accent = colors.tertiary,
      colors = colors,
    }))
    shell.add(kit.spacer(kit.SPACING.cardGap))
    shell.add(metricPair({
      title = "练习天数",
      value = formatter.int(data.days.count),
      suffix = "天",
      detail = string.format("日均 %s 分钟 · 本月日均 %s 分钟",
        formatter.number(data.days.avg), formatter.int(data.days.monthAvg)),
      accent = colors.secondary,
      colors = colors,
    }, {
      title = "拍照练习",
      value = formatter.int(data.photo.count),
      suffix = "次",
      detail = string.format("月均 %s 次 · 本月 %s 次",
        formatter.number(data.photo.avg), formatter.int(data.photo.monthAvg)),
      accent = colors.primary,
      colors = colors,
    }))

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
    }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = 14 }))

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
    }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = 14 }))

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
      }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))
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
    -- 页面实例被路由缓存复用；已加载过就保留现有图表，不再整页重建。
    if not page.loaded then
      page.load(page.data == nil)
    end
  end

  -- 不在创建时渲染：首次渲染由 onShow -> load 完成，
  -- 否则会先闪一帧「暂无统计数据」空态再切成加载中。
  return page
end

return M
