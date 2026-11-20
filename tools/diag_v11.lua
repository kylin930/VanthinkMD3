-- v11：修复后验证。切 tab 时统计 loadlayout 增量与帧数，确认页面复用生效。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_main.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

-- 统计 loadlayout 次数
local lfTotal = 0
local realLoadlayout = loadlayout
loadlayout = function(...)
  lfTotal = lfTotal + 1
  return realLoadlayout(...)
end

local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"
local router = require "app.router"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() shell.showMain() end)
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(listener) end)
log("showMain 完成，loadlayout 总数 = " .. lfTotal)
flush()

local tabs = { "homework", "notifications", "statistics", "profile", "homework" }
local index = 0

local function sample(label, nextFn)
  local before = lfTotal
  draws = 0
  activity.delay(2000, function()
    log(string.format("[%s] 帧 %d，loadlayout 增量 %d，总数 %d", label, draws, lfTotal - before, lfTotal))
    flush()
    nextFn()
  end)
end

local function nextTab()
  index = index + 1
  local key = tabs[index]
  if key == nil then
    log("=== 结束 ===")
    flush()
    pcall(function() state.clearToken() end)
    print = rawPrint
    rawPrint("diag v11 done")
    return
  end
  pcall(function() router.showTab(key) end)
  sample("tab " .. key, nextTab)
end

activity.delay(2500, function()
  log("2.5 秒后 loadlayout 总数 = " .. lfTotal)
  flush()
  nextTab()
end)
