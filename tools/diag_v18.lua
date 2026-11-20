-- v18：稳态帧率验证。每次切 tab 后先等 2 秒让过渡动画结束，再采样 3 秒。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_steady.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local draws = 0
local layoutCount = 0
local drawListener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})
local layoutListener = luajava.createProxy("android.view.ViewTreeObserver$OnGlobalLayoutListener", {
  onGlobalLayout = function() layoutCount = layoutCount + 1 end,
})

require("app.services.homework").fetchList = function(opts, callback)
  local list = {}
  for i = 1, 5 do
    list[i] = { id = 1000 + i, name = "作业 " .. i, vanclass_name = "高一(3)班",
      type = { name = "普通模式" }, testbank_count = 12, completion_rate = i * 20,
      created_at = "2026/08/0" .. i }
  end
  callback(true, { list = list, total = 5, page = 1, hasMore = false })
end

require("app.services.notice").fetchList = function(opts, callback)
  local list = {}
  for i = 1, 4 do
    list[i] = { id = 2000 + i, content = "通知内容 " .. i, created_at = "2026/08/0" .. i,
      has_read = i % 2, sender = { nickname = "张老师" } }
  end
  callback(true, { list = list, count = 4, hasMore = false })
end

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"
local router = require "app.router"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() state.setAccount({ id = 12345, nickname = "测试同学" }) end)
pcall(function() shell.showMain() end)
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(drawListener) end)
pcall(function() shell.root.getViewTreeObserver().addOnGlobalLayoutListener(layoutListener) end)

local tabs = { "homework", "notifications", "statistics", "profile", "homework", "notifications" }
local index = 0

local function nextTab()
  index = index + 1
  local key = tabs[index]
  if key == nil then
    log("=== 结束 ===")
    flush()
    pcall(function() state.clearToken() end)
    print = rawPrint
    rawPrint("steady diag done")
    return
  end
  local ok, err = pcall(function() router.showTab(key) end)
  if not ok then
    log("FAIL showTab " .. key .. " :: " .. tostring(err):sub(1, 160))
    flush()
    nextTab()
    return
  end
  -- 先等 2 秒让过渡/加载动画结束
  activity.delay(2000, function()
    draws, layoutCount = 0, 0
    activity.delay(3000, function()
      log(string.format("%-14s 稳态 3 秒：绘制 %d 帧，布局 %d 次", key, draws, layoutCount))
      flush()
      nextTab()
    end)
  end)
end

activity.delay(2000, nextTab)
