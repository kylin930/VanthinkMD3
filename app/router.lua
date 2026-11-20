-- 页面路由：底部导航四个主页 + 可压栈的二级页。
-- 只负责视图切换与生命周期回调，不处理业务逻辑。

local theme = require "app.ui.theme"
local logger = require "app.utils.logger"

local M = {}

local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
local FrameLayoutParams = luajava.bindClass("android.widget.FrameLayout$LayoutParams")
local ViewGroupLayoutParams = luajava.bindClass("android.view.ViewGroup$LayoutParams")

M.container = nil
M.current = nil
M.currentKey = nil
M.stack = {}
M.tabs = {}
M.tabCache = {}
M.onTabChanged = nil

function M.init(container)
  M.container = container
end

local function detachAll()
  if M.container == nil then return end
  pcall(function() M.container.removeAllViews() end)
end

-- 把页面视图挂到内容容器：
-- 1) 视图若还挂在别的父容器上（二级页复用、缓存实例重挂），先移除，
--    否则 Android 会抛 "The specified child already has a parent"；
-- 2) 显式给 FrameLayout.LayoutParams(match, match)，保证页面铺满内容区。
--    独立 loadlayout 出来的根视图 LayoutParams 类型由控件自身决定，
--    不做这一步时非 FrameLayout 系控件可能得到 wrap 尺寸。
local function attachView(view)
  if view == nil or M.container == nil then return end
  pcall(function()
    local parent = view.getParent()
    if parent ~= nil then parent.removeView(view) end
  end)
  pcall(function()
    view.setLayoutParams(FrameLayoutParams(
      ViewGroupLayoutParams.MATCH_PARENT, ViewGroupLayoutParams.MATCH_PARENT))
  end)
  M.container.addView(view)
end

-- 离开当前页面
local function leaveCurrent()
  local current = M.current
  M.current = nil
  M.currentKey = nil
  if type(current) == "table" and current.onHide then
    pcall(current.onHide)
  end
  detachAll()
end

-- 注册底部导航页面
-- factory(): 返回 page 对象 { view = View, onShow = fn, onHide = fn, onResume = fn, title = string }
function M.registerTab(key, factory)
  M.tabs[key] = factory
end

function M.showTab(key)
  if M.container == nil then return end
  if M.currentKey == key and #M.stack == 0 then return end
  while #M.stack > 0 do
    local entry = table.remove(M.stack)
    if type(entry.page) == "table" and entry.page.onHide then
      pcall(entry.page.onHide)
    end
  end
  leaveCurrent()

  -- 主页页面实例按 key 缓存复用。
  -- 每次切 tab 都 factory() 重建整页会让页面从零开始构建（先空态、再加载态、
  -- 再列表），视觉上就是整屏闪几下，滚动位置也会丢。复用后切回只做 onShow。
  local page = M.tabCache[key]
  if page == nil then
    local factory = M.tabs[key]
    if factory == nil then
      logger.e("未注册的页面: " .. tostring(key))
      return
    end
    page = factory()
    M.tabCache[key] = page
  end
  M.current = page
  M.currentKey = key
  attachView(page.view)
  if page.onShow then pcall(page.onShow) end
  if M.onTabChanged then pcall(M.onTabChanged, key) end
  return page
end

-- 丢弃所有缓存的主页实例（外壳重建、登录态切换时必须调用）
function M.clearTabCache()
  M.tabCache = {}
end

-- 压栈打开二级页；返回 page
function M.push(page)
  if M.container == nil or page == nil then return end
  if M.current ~= nil then
    M.stack[#M.stack + 1] = { key = M.currentKey, page = M.current }
    detachAll()
    if M.current.onPause then pcall(M.current.onPause) end
  end
  M.current = page
  M.currentKey = page.key
  attachView(page.view)
  if page.onShow then pcall(page.onShow) end
  return page
end

function M.canGoBack()
  return #M.stack > 0
end

-- 返回上一层；返回 true 表示已处理
function M.back()
  if #M.stack == 0 then return false end
  local current = M.current
  if current ~= nil and current.onHide then pcall(current.onHide) end
  detachAll()
  local entry = table.remove(M.stack)
  M.current = entry.page
  M.currentKey = entry.key
  attachView(entry.page.view)
  if entry.page.onResume then pcall(entry.page.onResume) end
  if M.onTabChanged then pcall(M.onTabChanged, M.currentKey) end
  return true
end

-- 回到指定主页并清空栈
function M.reset(key)
  while #M.stack > 0 do
    local entry = table.remove(M.stack)
    if type(entry.page) == "table" and entry.page.onHide then
      pcall(entry.page.onHide)
    end
  end
  leaveCurrent()
  M.showTab(key)
end

-- 二级页通用外壳：顶部返回栏 + 内容区
function M.subPage(opts)
  local o = opts or {}
  local kit = require "app.ui.kit"
  local colors = theme.colors()

  local root
  local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
  root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = colors.surface,
  })

  local bar = loadlayout({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = "8dp",
    paddingEnd = "16dp",
    paddingTop = "8dp",
    paddingBottom = "8dp",
  })
  bar.addView(kit.iconButton("arrow_back", {
    onClick = function()
      if o.onBack then
        o.onBack()
      else
        M.back()
      end
    end,
  }))
  bar.addView(kit.text(o.title or "", {
    size = kit.TYPOGRAPHY.headline,
    color = colors.onSurface,
    bold = true,
  }))
  root.addView(bar)

  local contentHolder = loadlayout({
    FrameLayout,
    layout_width = "match",
    layout_height = "wrap",
  })
  -- FrameLayout 根视图的 LayoutParams 没有 weight；高度 0dp + 无效 weight
  -- 会让内容区高度为 0。这里显式设置为 LinearLayout.LayoutParams。
  kit.applyLinearParams(contentHolder, { width = "match", height = "0dp", weight = 1 })
  root.addView(contentHolder)

  -- 挂载正文：先清空并处理旧父容器，再显式给 match/match 的 FrameLayout.LayoutParams，
  -- 保证页面正文（ScrollView / SwipeRefreshLayout 等）真正填满返回栏以下的内容区。
  local function setContent(view)
    pcall(function() contentHolder.removeAllViews() end)
    if view == nil then return end
    pcall(function()
      local parent = view.getParent()
      if parent ~= nil then parent.removeView(view) end
    end)
    pcall(function()
      view.setLayoutParams(FrameLayoutParams(
        ViewGroupLayoutParams.MATCH_PARENT, ViewGroupLayoutParams.MATCH_PARENT))
    end)
    contentHolder.addView(view)
  end

  -- 关键修复：此前只创建了内容容器，从未挂载 opts.content，
  -- 于是所有 router.subPage({ content = shell.root }) 的二级页只有返回栏，正文空白。
  setContent(o.content)

  return {
    root = root,
    bar = bar,
    content = contentHolder,
    setContent = setContent,
  }
end

return M
