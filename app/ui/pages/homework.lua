-- 作业首页：筛选、分页列表、下拉刷新、加载/空/错误状态。
-- 渲染策略：外壳（标题/摘要/筛选）只构建一次，刷新与分页只重建列表区，
-- 避免整页重建造成的闪烁与滚动位置丢失。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local config = require "app.config"
local state = require "app.state"
local homeworkService = require "app.services.homework"
local formatter = require "app.utils.formatter"

local M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
local ChipGroup = luajava.bindClass("com.google.android.material.chip.ChipGroup")
local Chip = luajava.bindClass("com.google.android.material.chip.Chip")

local function completionPercent(item)
  local rate = tonumber(item.completion_rate)
  if rate == nil then return 0 end
  if rate > 0 and rate <= 1 then rate = rate * 100 end
  return math.max(0, math.min(100, rate))
end

local function statusBadge(item, colors)
  local percent = completionPercent(item)
  if percent >= 100 then
    return kit.badge("已完成", {
      background = colors.tertiaryContainer,
      color = colors.onTertiaryContainer,
    })
  end
  if percent > 0 then
    return kit.badge("进行中", {
      background = colors.primaryContainer,
      color = colors.onPrimaryContainer,
    })
  end
  return kit.badge("未开始", {
    background = colors.surfaceContainerHighest,
    color = colors.onSurfaceVariant,
  })
end

local function buildCard(item, colors, onOpen)
  local className = item.vanclass_name or "已退班"
  if className == "" then className = "已退班" end
  local typeName = (type(item["type"]) == "table" and item["type"].name) or "普通模式"
  local count = tonumber(item.testbank_count) or 0
  local percent = completionPercent(item)

  local children = {
    kit.row({
      kit.column({
        kit.text(item.name or "未命名作业", {
          size = kit.TYPOGRAPHY.title,
          color = colors.onSurface,
          bold = true,
          maxLines = 2,
        }),
      }, { width = "0dp", weight = 1 }),
      statusBadge(item, colors),
    }, { width = "match" }),
    kit.spacer(6),
    kit.text(string.format("%s · %s · %s", className, typeName,
      formatter.friendlyTime(item.created_at)), {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      maxLines = 2,
    }),
    kit.spacer(12),
    kit.row({
      require("app.ui.chart").progressRing(percent, 38),
      kit.column({
        kit.text(string.format("完成度 %s", formatter.percent(percent)), {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
        }),
        kit.spacer(2),
        kit.text(string.format("%d 个练习", count), {
          size = kit.TYPOGRAPHY.label,
          color = colors.outline,
        }),
      }, { width = "0dp", weight = 1, marginStart = 12 }),
    }, { width = "match" }),
  }

  if item.description ~= nil and tostring(item.description) ~= "" then
    children[#children + 1] = kit.spacer(8)
    children[#children + 1] = kit.text(tostring(item.description), {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      maxLines = 2,
    })
  end

  return kit.card(children, {
    marginHorizontal = 16,
    marginTop = 8,
    marginBottom = 4,
    onClick = function() onOpen(item) end,
  })
end

function M.create()
  local colors = theme.colors()
  local page = {
    key = "homework",
    filter = { time = "all", degree = "all" },
    list = {},
    pageNo = 1,
    total = 0,
    hasMore = true,
    loading = false,
    loaded = false,
    error = nil,
  }

  local shell = kit.scrollPage({
    onRefresh = function() page.reload() end,
    onLoadMore = function() page.loadMore() end,
  })
  page.view = shell.root

  -- ===== 外壳（只构建一次）=====
  local summaryCount = kit.text("共 0 个作业", {
    size = kit.TYPOGRAPHY.headline,
    color = colors.onSurface,
    bold = true,
  })
  local summaryLoaded = kit.text("已加载 0", {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
  })
  local accountLabel = kit.text("尚未获取账号信息", {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
  })

  local function updateSummary()
    summaryCount.setText(string.format("共 %s 个作业", formatter.int(page.total)))
    summaryLoaded.setText(string.format("已加载 %d", #page.list))
    local account = state.account
    if type(account) == "table" and account.nickname then
      accountLabel.setText(tostring(account.nickname))
    else
      accountLabel.setText("尚未获取账号信息")
    end
  end

  -- 筛选 chip 的选中态由页面状态驱动；切换筛选时只刷新选中状态与列表
  local chipByKey = {}

  local function buildFilterGroup(title, options, groupKey, onSelect)
    local holder = loadlayout({
      ChipGroup,
      layout_width = "wrap",
      layout_height = "wrap",
      singleLine = true,
      singleSelection = true,
      chipSpacingHorizontal = "8dp",
    })
    for _, option in ipairs(options) do
      local chip = Chip(activity)
      chip.setText(option.label)
      chip.setCheckable(true)
      chip.setTag(option.key)
      local key = groupKey .. ":" .. option.key
      chipByKey[key] = chip
      chip.setOnClickListener(function()
        if page.filter[groupKey] == option.key then return end
        page.filter[groupKey] = option.key
        page.syncFilter()
        onSelect(option.key)
      end)
      holder.addView(chip)
    end
    return kit.column({
      kit.text(title, { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
      kit.spacer(6),
      holder,
    }, { width = "wrap" })
  end

  function page.syncFilter()
    for _, option in ipairs(config.TIME_FILTERS) do
      local chip = chipByKey["time:" .. option.key]
      if chip ~= nil then
        chip.setChecked(page.filter.time == option.key)
      end
    end
    for _, option in ipairs(config.DEGREE_FILTERS) do
      local chip = chipByKey["degree:" .. option.key]
      if chip ~= nil then
        chip.setChecked(page.filter.degree == option.key)
      end
    end
  end

  local filterScroll = loadlayout({
    HorizontalScrollView,
    layout_width = "match",
    layout_height = "wrap",
  })
  -- scrollbars 不是 setter/field 属性，必须在加载后调用原生方法关闭
  pcall(function()
    filterScroll.setHorizontalScrollBarEnabled(false)
    filterScroll.setVerticalScrollBarEnabled(false)
  end)
  local filterInner = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "wrap",
    layout_height = "wrap",
    paddingStart = "16dp",
    paddingEnd = "16dp",
  })
  filterInner.addView(buildFilterGroup("时间范围", config.TIME_FILTERS, "time", function()
    page.reload()
  end))
  filterInner.addView(kit.spacer(8))
  filterInner.addView(buildFilterGroup("完成状态", config.DEGREE_FILTERS, "degree", function()
    page.reload()
  end))
  filterScroll.addView(filterInner)

  -- 列表区容器
  local body = kit.column({}, { width = "match" })

  shell.add(kit.pageHeader("作业", nil, {
    kit.iconButton("refresh", { onClick = function() page.reload() end }),
  }))
  shell.add(kit.row({
    accountLabel,
    kit.column({}, { width = "0dp", weight = 1 }),
  }, { width = "match", paddingStart = 20, paddingEnd = 20, paddingBottom = 8 }))
  shell.add(kit.card({
    kit.text("当前筛选结果", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
    kit.spacer(8),
    kit.row({
      summaryCount,
      kit.column({}, { width = "0dp", weight = 1 }),
      summaryLoaded,
    }, { width = "match" }),
  }, { marginHorizontal = 16, padding = 16 }))
  shell.add(kit.spacer(10))
  shell.add(filterScroll)
  shell.add(kit.spacer(4))
  shell.add(body)

  page.syncFilter()

  -- ===== 列表区渲染 =====
  -- 列表区结构固定为：[卡片 1..N][页脚]。
  -- 分页加载只追加新卡片并替换页脚，不做整块 removeAllViews 重建，
  -- 否则每次「加载更多」都会把已有卡片销毁重建，列表会明显闪一下。
  local cardViews = {}
  local footerView = nil
  -- 状态占位（加载中 / 空态 / 错误）的引用，切回列表时必须显式移除
  local statusView = nil

  local function openCard(item)
    local detail = require "app.ui.pages.homework_detail"
    local router = require "app.router"
    router.push(detail.create(item))
  end

  local footerKey = nil

  local function clearBody()
    body.removeAllViews()
    cardViews = {}
    footerView = nil
    footerKey = nil
    statusView = nil
  end

  local function buildFooter()
    if page.hasMore then
      if page.loading then
        return kit.row({
          kit.spinner(20),
          kit.text("加载更多…", {
            size = kit.TYPOGRAPHY.label,
            color = colors.onSurfaceVariant,
            marginStart = 8,
          }),
        }, { width = "match", padding = 16, gravity = "center" })
      end
      return kit.row({
        kit.button("加载更多", {
          style = "outlined",
          height = "40dp",
          size = kit.TYPOGRAPHY.label,
          onClick = function() page.loadMore() end,
        }),
      }, { width = "match", padding = 12, gravity = "center" })
    end
    return kit.row({
      kit.text("已经到底了", { size = kit.TYPOGRAPHY.label, color = colors.outline }),
    }, { width = "match", padding = 16, gravity = "center" })
  end

  -- 页脚只在形态变化时重建，相同形态复用同一个 View，避免多余的重排
  local function applyFooter()
    local key = (not page.hasMore) and "end" or (page.loading and "loading" or "more")
    if footerView ~= nil and footerKey == key then return end
    if footerView ~= nil then body.removeView(footerView) end
    footerKey = key
    footerView = buildFooter()
    body.addView(footerView)
  end

  -- 状态占位（加载中 / 空态 / 错误）必须单独记账。
  -- 之前它被 addView 进 body 后没有跟踪：数据返回、开始追加列表卡片时不会被移除，
  -- 其中的 CircularProgressIndicator 会继续每帧 invalidate，
  -- 整个主界面因此持续重绘（表现为一直闪烁）。切回列表时必须显式移除。
  local function renderStatus(view)
    clearBody()
    statusView = view
    if view ~= nil then body.addView(view) end
  end

  local function renderBody()
    if page.error ~= nil then
      renderStatus(kit.stateView({
        icon = "cloud_off",
        title = "作业加载失败",
        message = page.error,
        actionLabel = "重试",
        actionIcon = "refresh",
        onAction = function() page.reload() end,
      }))
      return
    end

    if #page.list == 0 then
      if page.loading then
        renderStatus(kit.row({
          kit.spinner(24),
          kit.text("正在加载作业…", {
            size = kit.TYPOGRAPHY.body,
            color = colors.onSurfaceVariant,
            marginStart = 12,
          }),
        }, { width = "match", padding = 28, gravity = "center" }))
      else
        renderStatus(kit.stateView({
          icon = "task_alt",
          title = "没有符合条件的作业",
          message = "换个筛选条件，或下拉刷新试试",
          actionLabel = "重置筛选",
          onAction = function()
            page.filter = { time = "all", degree = "all" }
            page.syncFilter()
            page.reload()
          end,
        }))
      end
      return
    end

    if statusView ~= nil then
      pcall(function() body.removeView(statusView) end)
      statusView = nil
    end

    -- 列表被替换（数量减少）时无法安全增量追加，回退到整块重建
    if #cardViews > #page.list then clearBody() end
    for index = #cardViews + 1, #page.list do
      local view = buildCard(page.list[index], colors, openCard)
      cardViews[index] = view
      body.addView(view)
    end
    applyFooter()
  end

  function page.render()
    updateSummary()
    renderBody()
  end

  function page.load(reset)
    if page.loading then return end
    if not state.isLoggedIn() then
      page.error = "登录状态已失效，请重新登录"
      page.loaded = true
      page.render()
      return
    end
    page.loading = true
    if reset then
      -- 刷新时不清空 page.list：清空会让已有卡片瞬间消失，出现「整页变空再重新填充」
      -- 的闪烁。这里只重置分页游标，并把本次结果标记为整体替换。
      page.pageNo = 1
      page.hasMore = true
      page.replaceOnResult = true
    end
    page.error = nil
    renderBody()

    homeworkService.fetchList({
      page = page.pageNo,
      time = page.filter.time,
      degree = page.filter.degree,
    }, function(ok, data, result)
      page.loading = false
      page.loaded = true
      shell.setRefreshing(false)
      if not ok then
        page.replaceOnResult = false
        page.error = tostring(data)
        page.render()
        if result ~= nil and result.kind == "auth" then
          require "app.ui.pages.login".showAuthExpired()
        end
        return
      end
      if page.replaceOnResult then
        page.replaceOnResult = false
        page.list = data.list
      else
        for _, item in ipairs(data.list) do
          page.list[#page.list + 1] = item
        end
      end
      page.total = data.total
      page.hasMore = data.hasMore
      if page.hasMore then page.pageNo = page.pageNo + 1 end
      page.render()
    end)
  end

  function page.reload()
    page.load(true)
  end

  function page.loadMore()
    if not page.hasMore or page.loading or page.error ~= nil then return end
    page.load(false)
  end

  function page.onShow()
    updateSummary()
    -- 已加载过就保留现有视图不动：页面实例被路由缓存复用，
    -- 切回该 tab 时若重建列表，画面会出现明显跳变。
    if not page.loaded then
      page.load(true)
    end
  end

  -- 不在创建时渲染：首次渲染由 onShow -> load 完成。
  updateSummary()
  return page
end

return M
