-- 登录页输入框宽度验证：测量 edit 与卡片实际尺寸。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_login.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"

pcall(function() theme.bootstrap() end)
pcall(function() state.reset() end)
pcall(function() shell.init() end)
pcall(function() shell.start() end)
log("mode=" .. tostring(shell.mode))

local function walk(view, depth, out)
  out[#out + 1] = { view = view, depth = depth }
  local ok, count = pcall(function() return view.getChildCount() end)
  if ok and type(count) == "number" and count > 0 then
    for i = 0, count - 1 do walk(view.getChildAt(i), depth + 1, out) end
  end
  return out
end

activity.delay(2000, function()
  local nodes = walk(shell.root, 0, {})
  log("视图数 = " .. #nodes)
  local dpi = activity.getResources().getDisplayMetrics().density
  for _, node in ipairs(nodes) do
    local name = tostring(node.view.getClass().getSimpleName())
    local w, h = node.view.getWidth(), node.view.getHeight()
    local mark = ""
    if string.find(name, "EditText") ~= nil then
      mark = (w > 0) and "   <== 宽度正常" or "   <== 宽度为 0，异常"
    end
    log(string.format("%s%s %dx%d (%.0fdp x %.0fdp)%s", string.rep("  ", node.depth),
      name, w, h, w / dpi, h / dpi, mark))
    flush()
  end
  log("=== 结束 ===")
  flush()
  print = rawPrint
  rawPrint("login diag done")
end)
