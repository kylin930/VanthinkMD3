-- UI 组件诊断（开发期工具）：逐个构造组件并捕获异常与 loadlayout 日志
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_ui.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
local captured = {}
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  captured[#captured + 1] = table.concat(parts, "\t")
  flush()
end

local function drain()
  if #captured == 0 then return end
  for _, text in ipairs(captured) do
    log("      LOG " .. text:gsub("\n", " "):sub(1, 400))
  end
  captured = {}
  flush()
end

local function step(label, fn)
  local ok, err = pcall(fn)
  if ok then log("OK    " .. label)
  else log("FAIL  " .. label .. " :: " .. tostring(err):gsub("\n", " "):sub(1, 500)) end
  drain()
  flush()
end

step("require theme/kit", function()
  require "app.ui.theme"
  require "app.ui.kit"
end)

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local colors = theme.colors()

step("kit.text 基本", function() assert(kit.text("文本", { size = 14 }) ~= nil) end)
step("kit.text maxLines", function() kit.text("t", { maxLines = 2, bold = true, marginStart = 4 }) end)
step("kit.text match", function() kit.text("居中", { width = "match", gravity = "center" }) end)
step("kit.spacer", function() kit.spacer(12) end)
step("kit.divider", function() kit.divider(0, 0) end)
step("kit.column", function() kit.column({ kit.text("a") }, { padding = 16, id = "colTest" }) end)
step("kit.row weight", function()
  kit.row({ kit.column({}, { width = "0dp", weight = 1 }), kit.text("右") }, { width = "match" })
end)
step("kit.icon", function() assert(kit.icon("assignment", 22, colors.primary) ~= nil) end)
step("kit.centeredParams", function() assert(kit.centeredParams() ~= nil) end)
step("kit.colorDot", function() kit.colorDot(44, colors.primaryContainer, colors.primary) end)
step("kit.pill nil", function() kit.pill(nil, {}) end)
step("kit.badge", function() kit.badge("已完成", {}) end)
step("kit.card", function() kit.card({ kit.text("内容") }, { padding = 16 }) end)
step("kit.card padding0", function() kit.card({ kit.text("x") }, { padding = 0, marginHorizontal = 16 }) end)
step("kit.card weight", function() kit.card({ kit.text("x") }, { width = "0dp", weight = 1 }) end)
step("kit.button", function() assert(kit.button("确定", { onClick = function() end }) ~= nil) end)
step("kit.button outlined", function() kit.button("取消", { style = "outlined", height = "40dp", size = 12 }) end)
step("kit.button icon", function() kit.button("复制", { style = "text", iconName = "copy" }) end)
step("kit.button match", function() kit.button("登录", { width = "match", height = "52dp" }) end)
step("kit.iconButton", function() assert(kit.iconButton("refresh", {}) ~= nil) end)
step("kit.listItem", function()
  kit.listItem({ icon = "qr_code", title = "标题", subtitle = "副标题", showChevron = true,
    onClick = function() end })
end)
step("kit.listItem 无图标", function() kit.listItem({ title = "标题", trailingText = "值" }) end)
step("kit.linearProgress", function() kit.linearProgress(false) end)
step("kit.spinner", function() kit.spinner(24) end)
step("kit.stateView", function()
  kit.stateView({ icon = "cloud_off", title = "标题", message = "说明",
    actionLabel = "重试", actionIcon = "refresh", onAction = function() end })
end)
step("kit.scrollPage", function()
  local page = kit.scrollPage({ onRefresh = function() end, onLoadMore = function() end })
  page.add(kit.text("内容"))
  page.setRefreshing(false)
end)
step("kit.pageHeader", function() kit.pageHeader("标题", "副标题", { kit.iconButton("refresh", {}) }) end)
step("kit.sectionTitle", function() kit.sectionTitle("分组", "查看全部", function() end) end)
step("kit.group", function()
  kit.group({ kit.listItem({ icon = "info", title = "A" }), kit.listItem({ icon = "info", title = "B" }) })
end)

step("ChipGroup", function()
  local ChipGroup = luajava.bindClass("com.google.android.material.chip.ChipGroup")
  local Chip = luajava.bindClass("com.google.android.material.chip.Chip")
  local holder = loadlayout({
    ChipGroup, layout_width = "wrap", layout_height = "wrap",
    singleLine = true, singleSelection = true, chipSpacingHorizontal = "8dp",
  })
  local chip = Chip(activity)
  chip.setText("全部")
  chip.setCheckable(true)
  chip.setChecked(true)
  holder.addView(chip)
end)

step("HorizontalScrollView", function()
  local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
  local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
  local scroll = loadlayout({
    HorizontalScrollView, layout_width = "match", layout_height = "wrap", scrollbars = "none" })
  scroll.addView(loadlayout({
    LinearLayout, orientation = "vertical", layout_width = "wrap", layout_height = "wrap",
    paddingStart = "16dp", paddingEnd = "16dp" }))
end)

step("BottomNavigationView", function()
  local BottomNavigationView = luajava.bindClass(
    "com.google.android.material.bottomnavigation.BottomNavigationView")
  local nav = BottomNavigationView(activity)
  pcall(function()
    nav.setBackgroundColor(colors.surfaceContainer)
    nav.setLabelVisibilityMode(1)
  end)
  local menu = nav.getMenu()
  menu.clear()
  local icons = require "app.ui.icons"
  for index = 1, 4 do
    local item = menu.add(0, index, index - 1, "T" .. index)
    local drawable = icons.get("assignment", 22, colors.onSurfaceVariant)
    if drawable ~= nil then item.setIcon(drawable) end
  end
  assert(menu.size() == 4)
end)

step("MaterialTextField 手机号", function()
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
  local field = loadlayout({
    MaterialTextField, layout_width = "match", layout_height = "wrap", hint = "手机号",
    singleLine = true, inputType = "phone",
    style = MaterialStyle.Widget_Material3_TextInputLayout_OutlinedBox,
    tintColor = colors.primary,
  })
  field.setText("13800138000")
  assert(tostring(field.getText()) == "13800138000")
end)

step("MaterialTextField number", function()
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
  loadlayout({
    MaterialTextField, layout_width = "match", layout_height = "wrap", hint = "耗时",
    singleLine = true, inputType = "number",
    style = MaterialStyle.Widget_Material3_TextInputLayout_OutlinedBox,
    tintColor = colors.primary,
  })
end)

step("MaterialTextField minLines", function()
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
  loadlayout({
    MaterialTextField, layout_width = "match", layout_height = "wrap", hint = "链接",
    singleLine = false, minLines = 2,
    style = MaterialStyle.Widget_Material3_TextInputLayout_OutlinedBox,
    tintColor = colors.primary,
  })
end)

step("ImageView", function()
  local ImageView = luajava.bindClass("android.widget.ImageView")
  loadlayout({ ImageView, layout_width = "60dp", layout_height = "60dp", scaleType = "centerCrop" })
end)

step("ImageView adjustViewBounds", function()
  local ImageView = luajava.bindClass("android.widget.ImageView")
  loadlayout({ ImageView, layout_width = "match", layout_height = "wrap",
    adjustViewBounds = true, scaleType = "fitCenter" })
end)

step("FrameLayout weight", function()
  local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
  loadlayout({ FrameLayout, layout_width = "match", layout_height = "0dp", layout_weight = 1 })
end)

step("NestedScrollView", function()
  local ScrollView = luajava.bindClass("androidx.core.widget.NestedScrollView")
  loadlayout({ ScrollView, layout_width = "match", layout_height = "match", fillViewport = true })
end)

step("chart.barChart", function()
  local points = {}
  for i = 1, 8 do points[i] = { label = "01/0" .. i, value = i * 2 } end
  assert(require("app.ui.chart").barChart({ points = points }) ~= nil)
end)

step("chart.qrCode", function()
  local qrcode = require "app.utils.qrcode"
  assert(require("app.ui.chart").qrCode(qrcode.encode("https://zxzjurl.930390.xyz/t"), 200) ~= nil)
end)

step("chart.progressRing", function()
  assert(require("app.ui.chart").progressRing(100, 38) ~= nil)
end)

step("头像裁剪", function()
  local ImageView = luajava.bindClass("android.widget.ImageView")
  local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
  local view = loadlayout({ ImageView, layout_width = "60dp", layout_height = "60dp" })
  local drawable = GradientDrawable()
  drawable.setShape(GradientDrawable.OVAL)
  drawable.setColor(theme.normalize(colors.surfaceContainerHighest))
  view.setBackground(drawable)
  view.setClipToOutline(true)
end)

log("=== 诊断结束 ===")
flush()
print = rawPrint
print("diag ui done")
