-- 隔离测试 D: 完整启动路径 bootstrap -> shell.init -> shell.start
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoD.txt"

local function append(text)
  local previous = ""
  pcall(function() previous = LFU.read(OUT) or "" end)
  pcall(function() LFU.writeOrCreate(OUT, previous .. tostring(text) .. "\n") end)
end

local rawPrint = print
print = function() end

append("SCRIPT_START " .. tostring(os.time()) .. " activity=" .. tostring(activity))

function onCreate()
  append("ONCREATE " .. tostring(os.time()))
end

require "app.ui.theme".bootstrap()
append("after theme")

local shell = require "app.ui.shell"
shell.init()
append("after shell.init")

shell.start()
append("after shell.start mode=" .. tostring(shell.mode))

activity.delay(3000, function()
  append("CHECK_3S activity=" .. tostring(activity))
end)

activity.delay(6000, function()
  append("CHECK_6S activity=" .. tostring(activity))
  print = rawPrint
  rawPrint("iso D done")
end)
