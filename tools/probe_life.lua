-- 生命周期诊断：确认 AppCompatDelegate 常量与初始值，并检测 Activity 是否被重建
-- 结果写入 _probe_life.txt
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_life.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

log("=== AppCompatDelegate 常量实测 ===")
local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")

local function show(name)
  local ok, value = pcall(function() return AppCompatDelegate[name] end)
  log(string.format("  %-28s ok=%s value=%s (type=%s)", name, tostring(ok),
    tostring(value), type(value)))
end

show("MODE_NIGHT_FOLLOW_SYSTEM")
show("MODE_NIGHT_NO")
show("MODE_NIGHT_YES")
show("MODE_NIGHT_AUTO_TIME")
show("MODE_NIGHT_AUTO_BATTERY")
show("MODE_NIGHT_UNSPECIFIED")
flush()

local ok, current = pcall(function() return AppCompatDelegate.getDefaultNightMode() end)
log("getDefaultNightMode() = " .. tostring(current) .. " (ok=" .. tostring(ok) .. ")")
flush()

-- 关键判定：当前值是否为 -100（UNSPECIFIED）
local isUnspecified = ok and tonumber(current) == -100
log("当前是否为 UNSPECIFIED(-100): " .. tostring(isUnspecified))
flush()

log("")
log("=== 模拟 theme.applyMode 的判定逻辑 ===")
local config = require "app.config"
local pref = require "app.storage.preferences"
local mode = pref.getString("theme_mode", config.THEME_MODE.SYSTEM)
log("存储的 theme_mode = " .. tostring(mode))

-- 复现 theme.lua 中的判断，看会不会误判为"需要设置"
local target = config.THEME_MODE.SYSTEM
local nightMode = AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
log("目标 nightMode = " .. tostring(nightMode))
local unspecified = AppCompatDelegate.MODE_NIGHT_UNSPECIFIED
log("MODE_NIGHT_UNSPECIFIED = " .. tostring(unspecified))
local wouldSkip = false
if nightMode == AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM then
  local skipByFollow = (current == AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
  local skipByUnspecified = (unspecified ~= nil and current == unspecified)
  log("  skipByFollowSystem = " .. tostring(skipByFollow))
  log("  skipByUnspecified  = " .. tostring(skipByUnspecified))
  wouldSkip = skipByFollow or skipByUnspecified
end
if not wouldSkip and current == nightMode then wouldSkip = true end
log("结论：是否会调用 setDefaultNightMode = " .. tostring(not wouldSkip))
flush()

print = rawPrint
print("probe_life done")
