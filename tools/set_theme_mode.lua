-- 切换深浅色模式（开发期工具，用于「浅色 / 深色」两套 UI 回归）
-- 运行方式：以本文件为入口运行。不带参数时在 light / dark 之间切换；
-- 把 MODE 改成具体值时直接切到该模式。
--
-- 说明：只写入偏好并设置 AppCompatDelegate，不主动 recreate，
-- 这样随后启动的回归脚本/应用入口会以新模式的色板启动。

local MODE = nil -- "light" / "dark" / nil（在两者间切换）

local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_theme_mode.txt"

local theme = require "app.ui.theme"
local config = require "app.config"
local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")

local target = MODE
if target == nil then
  local current = theme.mode()
  target = (current == config.THEME_MODE.DARK) and config.THEME_MODE.LIGHT or config.THEME_MODE.DARK
end

local changed = theme.applyMode(target, false)
local nightMode = (target == config.THEME_MODE.DARK)
  and AppCompatDelegate.MODE_NIGHT_YES or AppCompatDelegate.MODE_NIGHT_NO
pcall(function() AppCompatDelegate.setDefaultNightMode(nightMode) end)

local report = string.format("mode=%s changed=%s delegate=%s",
  tostring(target), tostring(changed), tostring(AppCompatDelegate.getDefaultNightMode()))
pcall(function() LFU.writeOrCreate(OUT, report) end)
print("set_theme_mode: " .. report)
