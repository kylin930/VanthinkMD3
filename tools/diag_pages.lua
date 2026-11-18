-- 页面级诊断（开发期工具）
-- 劫持 print 捕获 loadlayout 的“属性错误”输出，复现未登录/已登录两条启动路径，
-- 并记录每个阶段是否抛异常。结果写入 _diag_pages.txt。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_pages.txt"
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

local function drain(tag)
  if #captured == 0 then
    log("      (无日志输出)")
    return
  end
  for _, text in ipairs(captured) do
    log("      [" .. tag .. "] " .. text:gsub("\n", " "):sub(1, 500))
  end
  captured = {}
  flush()
end

local function step(label, fn)
  captured = {}
  local ok, err = pcall(fn)
  if ok then log("OK    " .. label)
  else log("FAIL  " .. label .. " :: " .. tostring(err):gsub("\n", " "):sub(1, 600)) end
  drain(label)
end

-- ===== 阶段 1：未登录 → 登录页 =====
step("state.bootstrap(清空登录态)", function()
  local state = require "app.state"
  state.reset()
  state.bootstrap()
  assert(not state.isLoggedIn())
end)

step("shell.init", function()
  require "app.ui.shell".init()
end)

step("shell.showLogin", function()
  local theme = require "app.ui.theme"
  theme.bootstrap()
  require "app.ui.shell".showLogin()
end)

step("登录页字段交互", function()
  local dialogs = require "app.ui.dialogs"
  -- 不触发真实请求，只验证错误提示路径
  local kit = require "app.ui.kit"
  kit.text("验证", {})
end)

-- ===== 阶段 2：伪造已登录 → 主界面 =====
step("伪造 token", function()
  local state = require "app.state"
  state.setToken("diagnostic_fake_token_value")
  require "app.services.http".setTokenProvider(function() return state.token end)
end)

step("shell.showMain", function()
  require "app.ui.shell".showMain()
end)

local router = require "app.router"

step("showTab notifications", function() router.showTab("notifications") end)
step("showTab statistics", function() router.showTab("statistics") end)
step("showTab profile", function() router.showTab("profile") end)
step("showTab homework", function() router.showTab("homework") end)

-- ===== 阶段 3：二级页面 =====
step("作业详情页", function()
  local detail = require "app.ui.pages.homework_detail"
  router.push(detail.create({ id = "999999", name = "诊断作业", completion_rate = 42, testbank_count = 2 }))
end)
step("详情页返回", function() router.back() end)

step("主题设置页", function()
  local page = require "app.ui.pages.theme_settings".create()
  router.push(page)
end)
step("返回", function() router.back() end)

step("更新日志页", function()
  local page = require "app.ui.pages.changelog".create(true)
  router.push(page)
end)
step("返回", function() router.back() end)

step("关于页", function() local page = require "app.ui.pages.about".create(); router.push(page) end)
step("返回", function() router.back() end)

step("隐私与安全页", function()
  local page = require "app.ui.pages.security".create()
  router.push(page)
end)
step("返回", function() router.back() end)

step("对话框 alert", function()
  require "app.ui.dialogs".alert("诊断", "这是一条诊断对话框")
end)

step("对话框 confirm", function()
  require "app.ui.dialogs".confirm({ title = "诊断", message = "确认框", onConfirm = function() end })
end)

step("对话框 progress", function()
  local dialog = require "app.ui.dialogs".progress("加载中")
  dialog.dismiss()
end)

step("对话框 list", function()
  require "app.ui.dialogs".list({
    title = "诊断",
    items = { { label = "A", value = 1 }, { label = "B", value = 2 } },
    onSelect = function() end,
  })
end)

step("清理测试凭据", function()
  local state = require "app.state"
  state.reset()
end)

log("=== 页面诊断结束 ===")
flush()
print = rawPrint
print("diag pages done")
