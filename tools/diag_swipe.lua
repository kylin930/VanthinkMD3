-- 最小复现：SwipeRefreshLayout 在无交互时是否持续重绘。
-- 依次对比：仅 NestedScrollView / 套 SwipeRefreshLayout / 加 setColorSchemeColors / setEnabled(false)
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_swipe.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local NestedScrollView = luajava.bindClass("androidx.core.widget.NestedScrollView")
local SwipeRefreshLayout = luajava.bindClass("androidx.swiperefreshlayout.widget.SwipeRefreshLayout")

local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local colors = require("app.ui.theme").colors()

local function build(withRefresh, withColors)
  local content = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
  })
  content.addView(loadlayout({
    LinearLayout,
    layout_width = "match",
    layout_height = "400dp",
    BackgroundColor = colors.surfaceContainerLow,
  }))
  local scroll = loadlayout({
    NestedScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    BackgroundColor = colors.surface,
  })
  scroll.addView(content)
  if not withRefresh then return scroll end
  local refresh = SwipeRefreshLayout(activity)
  refresh.addView(scroll)
  if withColors then
    pcall(function()
      refresh.setColorSchemeColors({ colors.primary, colors.tertiary })
      refresh.setProgressBackgroundColorSchemeColor(colors.surfaceContainerHigh)
    end)
  end
  refresh.setOnRefreshListener(function() end)
  return refresh
end

local cases = {
  { label = "A 仅 ScrollView", refresh = false, colors = false },
  { label = "B SwipeRefreshLayout 默认", refresh = true, colors = false },
  { label = "C SwipeRefreshLayout + setColorSchemeColors", refresh = true, colors = true },
  { label = "D SwipeRefreshLayout + setEnabled(false)", refresh = true, colors = true, disable = true },
}

local index = 0

local function runCase()
  index = index + 1
  local item = cases[index]
  if item == nil then
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("swipe diag done")
    return
  end
  local view = build(item.refresh, item.colors)
  if item.disable then pcall(function() view.setEnabled(false) end) end
  activity.setContentView(view)
  activity.delay(1500, function()
    pcall(function() view.getViewTreeObserver().addOnDrawListener(listener) end)
    draws = 0
    activity.delay(2000, function()
      log(string.format("[%s] 2 秒内 %d 帧（约 %.1f 帧/秒）", item.label, draws, draws / 2))
      flush()
      runCase()
    end)
  end)
end

runCase()
