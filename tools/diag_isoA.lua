-- 重建隔离测试 A：只用 activity.delay，不加载主题、不构建界面
-- 若仍出现多次 SCRIPT_START，则重建与业务代码无关（属于 delay 或运行时行为）。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoA.txt"

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

activity.delay(3000, function()
  append("CHECK_3S activity=" .. tostring(activity))
end)

activity.delay(6000, function()
  append("CHECK_6S activity=" .. tostring(activity))
  print = rawPrint
  rawPrint("iso A done")
end)

activity.delay(9000, function()
  append("CHECK_9S activity=" .. tostring(activity))
end)
