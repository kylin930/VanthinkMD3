-- 隔离测试 E: 记录生命周期回调 + 每秒采样，定位 Activity 退出的时刻与原因
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoE.txt"

local function append(text)
  local previous = ""
  pcall(function() previous = LFU.read(OUT) or "" end)
  pcall(function() LFU.writeOrCreate(OUT, previous .. tostring(text) .. "\n") end)
end

local rawPrint = print
print = function() end

local tag = tostring(activity)
append("SCRIPT_START " .. tag)

function onCreate()
  append("  onCREATE " .. tostring(activity))
end

function onStart()
  append("  onStart " .. tostring(activity))
end

function onResume()
  append("  onResume " .. tostring(activity))
end

function onPause()
  append("  onPause " .. tostring(activity))
end

function onStop()
  append("  onStop " .. tostring(activity))
end

function onDestroy()
  append("  onDestroy " .. tostring(activity))
end

require "app.ui.theme".bootstrap()
local shell = require "app.ui.shell"
shell.init()
shell.start()
append("AFTER_START mode=" .. tostring(shell.mode))

-- 每秒独立采样 10 次（不使用嵌套 delay）
for index = 1, 10 do
  activity.delay(index * 1000, function()
    append(string.format("  TICK_%ds alive_activity=%s", index, tostring(activity)))
  end)
end
