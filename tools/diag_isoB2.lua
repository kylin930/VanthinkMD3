-- 隔离测试 B: theme.bootstrap 是否触发 Activity 重建
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoB.txt"

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

local theme = require "app.ui.theme"
append("mode=" .. tostring(theme.mode()) .. " seedSource=" .. tostring(theme.seedSource())
  .. " seedColor=" .. tostring(theme.seedColor()))

local ok, err = pcall(function() theme.bootstrap() end)
append("AFTER_BOOTSTRAP ok=" .. tostring(ok) .. " err=" .. tostring(err))

activity.delay(3000, function()
  append("CHECK_3S activity=" .. tostring(activity))
end)

activity.delay(6000, function()
  append("CHECK_6S activity=" .. tostring(activity))
  print = rawPrint
  rawPrint("iso B done")
end)
