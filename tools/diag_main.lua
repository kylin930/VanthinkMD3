-- v9：主界面中残留的进度指示器盘点，确认持续重绘的 spinner 位置。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_main.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local View = luajava.bindClass("android.view.View")
local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() shell.showMain() end)
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(listener) end)

local function collect(view, out)
  local className = tostring(view.getClass().getSimpleName())
  local count = 0
  local ok, n = pcall(function() return view.getChildCount() end)
  if ok and type(n) == "number" then count = n end
  out[#out + 1] = { view = view, className = className }
  for i = 0, count - 1 do collect(view.getChildAt(i), out) end
  return out
end

local progress = {}
local index = 0

local function testNext()
  index = index + 1
  local entry = progress[index]
  if entry == nil then
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("diag v9 done")
    return
  end
  if entry.view.getVisibility() == View.GONE then
    log("跳过 GONE: " .. entry.className)
    testNext()
    return
  end
  pcall(function() entry.view.setVisibility(View.GONE) end)
  draws = 0
  activity.delay(1200, function()
    log(string.format("[隐藏 %s] %d 帧/1.2 秒", entry.className, draws))
    flush()
    pcall(function() entry.view.setVisibility(View.VISIBLE) end)
    testNext()
  end)
end

activity.delay(4000, function()
  local nodes = collect(shell.root, {})
  log("节点数 = " .. #nodes)
  for _, node in ipairs(nodes) do
    if string.find(node.className, "Progress") ~= nil then
      progress[#progress + 1] = node
      log("进度控件 " .. node.className .. " visible=" .. tostring(node.view.getVisibility()))
    end
  end
  log("进度控件数 = " .. #progress)
  flush()
  draws = 0
  activity.delay(1500, function()
    log("基线 " .. draws .. " 帧/1.5 秒")
    flush()
    testNext()
  end)
end)
