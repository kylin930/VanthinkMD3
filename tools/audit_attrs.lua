-- loadlayout 属性审计（开发期工具）
-- loadlayout 对无法映射到 setter/field 的属性只打日志、不抛异常，
-- 因此这里劫持 print 捕获全部“不支持的属性 / 属性错误”输出，
-- 再遍历所有页面与组件，一次性列出全部非法属性名及其所在控件。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_audit_attrs.txt"
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
end

-- 只保留与属性相关的日志，其余（正常信息）丢弃以免淹没结果
local function drain(phase)
  if #captured == 0 then return end
  local seen = {}
  for _, text in ipairs(captured) do
    if string.find(text, "不支持的属性", 1, true)
      or string.find(text, "属性错误", 1, true)
      or string.find(text, "setter", 1, true) then
      local compact = text:gsub("%s+", " ")
      if not seen[compact] then
        seen[compact] = true
        log("  ATTR [" .. phase .. "] " .. compact:sub(1, 320))
      end
    end
  end
  captured = {}
  flush()
end

local problems = 0

local function phase(label, fn)
  captured = {}
  local ok, err = pcall(fn)
  if not ok then
    log("FAIL " .. label .. " :: " .. tostring(err):gsub("\n", " "):sub(1, 400))
  end
  local before = #lines
  drain(label)
  problems = problems + (#lines - before)
  log((ok and "done " or "ERROR ") .. label)
  flush()
end

phase("require", function()
  require "app.ui.theme"
  require "app.ui.kit"
end)

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
theme.bootstrap()
local colors = theme.colors()

-- ===== 逐组件审计（覆盖 kit 全部工厂方法）=====
phase("kit.text", function()
  kit.text("a", { size = 14, color = colors.onSurface })
  kit.text("b", { maxLines = 2, bold = true, marginStart = 4, marginTop = 2 })
  kit.text("c", { width = "match", gravity = "center" })
end)
phase("kit.spacer/divider", function() kit.spacer(12); kit.divider(4, 4) end)
phase("kit.column", function()
  kit.column({ kit.text("x") }, {
    padding = 16, paddingStart = 8, paddingEnd = 8, paddingTop = 4, paddingBottom = 4,
    marginTop = 4, marginBottom = 4, marginStart = 8, marginEnd = 8,
    gravity = "center_horizontal", background = colors.surfaceContainerLow, id = "c1",
  })
end)
phase("kit.row", function()
  kit.row({ kit.text("x") }, {
    width = "match", gravity = "start|center_vertical", padding = 8,
    paddingStart = 4, paddingEnd = 4, paddingTop = 2, paddingBottom = 2,
    marginTop = 4, background = colors.surface,
  })
end)
phase("kit.icon", function() kit.icon("assignment", 24, colors.primary) end)
phase("kit.colorDot", function() kit.colorDot(40, colors.primary, colors.outline) end)
phase("kit.pill", function() kit.pill(kit.text("p"), { strokeColor = colors.outline }) end)
phase("kit.badge", function() kit.badge("tag", {}) end)
phase("kit.card", function()
  kit.card({ kit.text("c") }, {
    width = "match", radius = 20, cardElevation = 0, strokeWidth = "1dp",
    strokeColor = colors.outlineVariant, background = colors.surfaceContainerLow,
    marginTop = 8, marginBottom = 8, marginHorizontal = 16, padding = 16,
    onClick = function() end,
  })
end)
phase("kit.button", function()
  kit.button("f", { width = "match", height = "48dp", size = 14, onClick = function() end })
  kit.button("o", { style = "outlined", height = "40dp", marginTop = 4, marginStart = 8, marginEnd = 8 })
  kit.button("t", { style = "text", iconName = "copy", iconColor = colors.primary })
end)
phase("kit.iconButton", function() kit.iconButton("refresh", { size = 44, iconSize = 22 }) end)
phase("kit.listItem", function()
  kit.listItem({
    icon = "info", title = "t", subtitle = "s", subtitleMaxLines = 2,
    trailingText = "v", showChevron = true, titleSize = 14, titleColor = colors.onSurface,
    subtitleColor = colors.onSurfaceVariant, paddingHorizontal = 16, paddingVertical = 14,
    onClick = function() end,
  })
end)
phase("kit.linearProgress", function() kit.linearProgress(false); kit.linearProgress(true) end)
phase("kit.spinner", function() kit.spinner(28) end)
phase("kit.stateView", function()
  kit.stateView({
    icon = "cloud_off", iconColor = colors.outline, title = "t", titleColor = colors.onSurface,
    message = "m", actionLabel = "重试", actionIcon = "refresh", onAction = function() end,
  })
end)
phase("kit.scrollPage", function()
  local p = kit.scrollPage({ onRefresh = function() end, onLoadMore = function() end })
  p.add(kit.text("x"))
end)
phase("kit.pageHeader", function() kit.pageHeader("T", "S", { kit.iconButton("refresh", {}) }) end)
phase("kit.sectionTitle", function() kit.sectionTitle("t", "a", function() end) end)
phase("kit.group", function() kit.group({ kit.listItem({ title = "a" }), kit.listItem({ title = "b" }) }) end)

-- ===== 页面级审计 =====
phase("page login", function()
  local shell = require "app.ui.shell"
  shell.init()
  shell.showLogin()
end)

phase("page homework(未登录态渲染)", function()
  require "app.ui.pages.homework".create()
end)

phase("page notifications", function()
  require "app.ui.pages.notifications".create()
end)

phase("page statistics", function()
  require "app.ui.pages.statistics".create()
end)

phase("page profile", function()
  require "app.ui.pages.profile".create()
end)

phase("page theme_settings", function()
  require "app.ui.pages.theme_settings".create()
end)

phase("page changelog", function()
  require "app.ui.pages.changelog".create(true)
end)

phase("page about", function()
  require "app.ui.pages.about".create()
end)

phase("page security", function()
  require "app.ui.pages.security".create()
end)

phase("page homework_detail", function()
  local page = require "app.ui.pages.homework_detail".create({
    id = "000", name = "审计作业", completion_rate = 50, testbank_count = 2,
  })
  assert(page.view ~= nil)
end)

phase("dialogs", function()
  local dialogs = require "app.ui.dialogs"
  dialogs.dismissAll()
  dialogs.progress("p")
  dialogs.dismissAll()
end)

log("")
log("=== 合计疑似问题行: " .. problems .. " ===")
if problems == 0 then
  log("RESULT: 未发现无效属性")
else
  log("RESULT: 存在无效属性，见上方 ATTR 行")
end
flush()
print = rawPrint
print("audit done")
