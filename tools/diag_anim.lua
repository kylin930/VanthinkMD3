-- 组件级重绘定位 v8：把单个组件放进最小页面，量化无交互时的帧率。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_anim.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local kit = require "app.ui.kit"
local colors = require("app.ui.theme").colors()

local function wrap(children)
  local root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    padding = "16dp",
    BackgroundColor = colors.surface,
  })
  for _, child in ipairs(children) do root.addView(child) end
  return root
end

local cases = {
  { label = "空 LinearLayout", build = function() return wrap({}) end },
  { label = "kit.spinner(24)", build = function() return wrap({ kit.spinner(24) }) end },
  { label = "kit.text", build = function() return wrap({ kit.text("作业", { size = 20, bold = true }) }) end },
  { label = "kit.text maxLines", build = function() return wrap({ kit.text("很长的一行文本内容用于测试", { maxLines = 2 }) }) end },
  { label = "kit.button", build = function() return wrap({ kit.button("登录", { width = "match" }) }) end },
  { label = "kit.button outlined", build = function() return wrap({ kit.button("重试", { style = "outlined" }) }) end },
  { label = "kit.iconButton", build = function() return wrap({ kit.iconButton("refresh", {}) }) end },
  { label = "kit.card", build = function() return wrap({ kit.card({ kit.text("卡片内容") }, { padding = 16 }) }) end },
  { label = "kit.badge", build = function() return wrap({ kit.badge("已完成", {}) }) end },
  { label = "kit.stateView", build = function()
    return wrap({ kit.stateView({ icon = "cloud_off", title = "加载失败", message = "网络错误",
      actionLabel = "重试", actionIcon = "refresh", onAction = function() end }) })
  end },
  { label = "kit.scrollPage 空", build = function()
    local page = kit.scrollPage({})
    return page.root
  end },
  { label = "kit.scrollPage + header + 列表", build = function()
    local page = kit.scrollPage({})
    page.add(kit.pageHeader("作业", nil, { kit.iconButton("refresh", {}) }))
    for i = 1, 5 do
      page.add(kit.card({ kit.text("卡片 " .. i) }, { padding = 16, marginHorizontal = 16 }))
    end
    return page.root
  end },
}

local index = 0

local function runCase()
  index = index + 1
  local item = cases[index]
  if item == nil then
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("anim diag done")
    return
  end
  local ok, view = pcall(item.build)
  if not ok or view == nil then
    log("FAIL " .. item.label .. " :: " .. tostring(view))
    flush()
    runCase()
    return
  end
  activity.setContentView(view)
  activity.delay(1200, function()
    pcall(function() view.getViewTreeObserver().addOnDrawListener(listener) end)
    draws = 0
    activity.delay(2000, function()
      log(string.format("%-28s %d 帧 / 2 秒", item.label, draws))
      flush()
      runCase()
    end)
  end)
end

runCase()
