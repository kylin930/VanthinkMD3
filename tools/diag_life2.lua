-- 生命周期诊断：用 onCreate 计数确认 Activity 是否被重建
-- 同时验证 theme.bootstrap()（含 dynamicColor）是否会触发重建
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_life.txt"

local function append(text)
  local previous = ""
  pcall(function() previous = LFU.read(OUT) or "" end)
  pcall(function() LFU.writeOrCreate(OUT, previous .. tostring(text) .. "\n") end)
end

local rawPrint = print
print = function() end

append("SCRIPT_START " .. tostring(os.time()) .. " activity=" .. tostring(activity))

function onCreate()
  append("ONCREATE " .. tostring(os.time()) .. " activity=" .. tostring(activity))
end

append("BEFORE_BOOTSTRAP")
local ok1, err1 = pcall(function()
  require "app.ui.theme".bootstrap()
end)
append("AFTER_BOOTSTRAP ok=" .. tostring(ok1) .. " err=" .. tostring(err1))

append("AFTER_BOOTSTRAP themeUtil.primary=" .. tostring(activity.themeUtil.primary.main))

-- 再次调用 dynamicColor，观察是否引发重建
local ok2, err2 = pcall(function()
  activity.dynamicColor()
end)
append("SECOND_DYNAMICCOLOR ok=" .. tostring(ok2) .. " err=" .. tostring(err2))

local shell = require "app.ui.shell"
append("BEFORE_SHELL_INIT")
shell.init()
append("AFTER_SHELL_INIT")
shell.start()
append("AFTER_SHELL_START")

-- 采样：3 秒与 6 秒后各记录一次（用独立的 delay 调用，避免嵌套延迟不可靠）
activity.delay(3000, function()
  append("CHECK_3S")
end)

activity.delay(6000, function()
  append("CHECK_6S")
  print = rawPrint
  rawPrint("life diag done")
end)
