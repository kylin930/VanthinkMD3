-- 模块与页面冒烟测试（开发期工具）
-- 逐个 require、构造页面、切换底部导航，把所有异常写入 _test_modules.txt
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_test_modules.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end

local function trace(err)
  return tostring(err)
end

local function attempt(label, fn)
  local ok, err = xpcall(fn, trace)
  if ok then
    log("PASS  " .. label)
  else
    log("FAIL  " .. label .. "\n      " .. tostring(err):gsub("\n", "\n      "))
  end
  flush()
  return ok
end

flush()

local MODULES = {
  "app.config",
  "app.storage.preferences",
  "app.storage.secure",
  "app.utils.logger",
  "app.utils.formatter",
  "app.utils.validator",
  "app.utils.qrcode",
  "app.services.http",
  "app.services.auth",
  "app.services.homework",
  "app.services.notice",
  "app.services.statistics",
  "app.services.share",
  "app.services.update",
  "app.services.transfer",
  "app.state",
  "app.router",
  "app.ui.theme",
  "app.ui.icons",
  "app.ui.kit",
  "app.ui.chart",
  "app.ui.dialogs",
  "app.ui.shell",
  "app.ui.pages.login",
  "app.ui.pages.homework",
  "app.ui.pages.homework_detail",
  "app.ui.pages.notifications",
  "app.ui.pages.statistics",
  "app.ui.pages.profile",
  "app.ui.pages.practice",
  "app.ui.pages.transfer",
  "app.ui.pages.theme_settings",
  "app.ui.pages.changelog",
  "app.ui.pages.about",
  "app.ui.pages.security",
}

for _, name in ipairs(MODULES) do
  attempt("require " .. name, function()
    local mod = require(name)
    assert(type(mod) == "table", name .. " 未返回 table")
  end)
end

-- 纯函数验证
attempt("formatter.parseDateTime", function()
  local f = require "app.utils.formatter"
  local parts = f.parseDateTime("2025-03-04 14:05:09")
  assert(parts.year == 2025 and parts.month == 3 and parts.day == 4, "解析结果错误")
  assert(f.duration(3725) == "1:02:05", "duration 错误: " .. f.duration(3725))
  assert(f.parseDuration("1:35") == 95, "parseDuration 错误")
end)

attempt("validator", function()
  local v = require "app.utils.validator"
  assert(v.isPhone("13800138000"))
  assert(not v.isPhone("1380013800"))
  assert(v.parseColor("#0061A4") == 0xFF0061A4)
  assert(v.parseColor("zzz") == nil)
  assert(v.colorToHex(0xFF0061A4) == "0061A4")
end)

attempt("secure 存取往返", function()
  local secure = require "app.storage.secure"
  local ok = secure.setSecret("test_secret", "hello-token-value")
  assert(ok, "写入失败")
  local value = secure.getSecret("test_secret")
  assert(value == "hello-token-value", "读取不一致: " .. tostring(value))
  secure.removeSecret("test_secret")
end)

attempt("theme.colors 完整性", function()
  local theme = require "app.ui.theme"
  local colors = theme.colors()
  for _, key in ipairs({ "primary", "onPrimary", "surface", "onSurface", "surfaceContainerLow",
    "surfaceContainerHigh", "outline", "outlineVariant", "error", "tertiary", "secondaryContainer" }) do
    assert(type(colors[key]) == "number", "缺少颜色角色: " .. key)
  end
end)

attempt("icons 生成", function()
  local icons = require "app.ui.icons"
  for _, name in ipairs({ "assignment", "notifications", "insights", "person", "refresh",
    "arrow_back", "share", "check", "qr_code", "leaderboard", "cloud_off", "warning" }) do
    local drawable = icons.get(name, 24, 0xFF112233)
    assert(drawable ~= nil, "图标生成失败: " .. name)
  end
end)

attempt("chart 绘制", function()
  local chart = require "app.ui.chart"
  local points = {}
  for i = 1, 10 do
    points[i] = { label = string.format("%02d/01", i), value = i * 3 }
  end
  assert(chart.barChart({ points = points }) ~= nil)
  assert(chart.lineChart({ points = points }) ~= nil)
  assert(chart.progressRing(42, 40) ~= nil)
  assert(chart.barChart({ points = {} }) ~= nil, "空数据应返回占位图")
end)

attempt("qrCode 渲染", function()
  local qrcode = require "app.utils.qrcode"
  local chart = require "app.ui.chart"
  local matrix = qrcode.encode("https://zxzjurl.930390.xyz/probe")
  assert(matrix ~= nil, "编码失败")
  assert(chart.qrCode(matrix, 200) ~= nil, "渲染失败")
end)

-- UI 构建
attempt("shell.init + showMain", function()
  local theme = require "app.ui.theme"
  theme.bootstrap()
  local shell = require "app.ui.shell"
  shell.init()
  shell.showMain()
end)

attempt("切换底部导航", function()
  local router = require "app.router"
  for _, key in ipairs({ "notifications", "statistics", "profile", "homework" }) do
    router.showTab(key)
  end
end)

attempt("打开作业详情页", function()
  local router = require "app.router"
  local detail = require "app.ui.pages.homework_detail"
  router.push(detail.create({ id = "000000", name = "测试作业", completion_rate = 42, testbank_count = 3 }))
end)

attempt("详情页返回", function()
  local router = require "app.router"
  assert(router.canGoBack(), "栈为空")
  router.back()
end)

attempt("主题预设色应用", function()
  local theme = require "app.ui.theme"
  theme.setSeed(0xFF0061A4)
  assert(theme.seedSource() == "seed")
  assert(theme.seedColor() == theme.normalize(0xFF0061A4),
    "种子色读取错误: " .. tostring(theme.seedColor()))
  theme.setFollowWallpaper()
end)

attempt("深浅色模式持久化", function()
  local theme = require "app.ui.theme"
  theme.applyMode("dark", false)
  assert(theme.mode() == "dark")
  theme.applyMode("system", false)
  assert(theme.mode() == "system")
end)

log("冒烟测试结束")
flush()
print("smoke done")
