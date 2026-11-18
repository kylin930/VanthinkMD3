-- 主题系统：MD3 颜色角色、尺寸/字号单位、深浅色与种子色。
-- 颜色统一从 activity.themeUtil 读取（跟随 dynamicColor 生成的色板），
-- 页面与组件不得硬编码颜色。

local config = require "app.config"
local pref = require "app.storage.preferences"

local M = {}

local TypedValue = luajava.bindClass("android.util.TypedValue")

-- ===== 单位 =====
function M.dp(value)
  local ok, px = pcall(function() return activity.dpToPx(value) end)
  if ok and px ~= nil then return math.floor(px + 0.5) end
  local density = activity.getResources().getDisplayMetrics().density
  return math.floor(value * density + 0.5)
end

function M.sp(value)
  local ok, px = pcall(function() return activity.spToPx(value) end)
  if ok and px ~= nil then return px end
  return value
end

-- ===== 颜色工具 =====
-- Lua 中 0xFFxxxxxx 为无符号正整数，Java int 需要 32 位有符号值；
-- 所有传给 Java 的颜色都必须先经过 normalize。
function M.normalize(color)
  local value = math.floor(tonumber(color) or 0)
  if value > 0x7FFFFFFF then
    return value - 0x100000000
  end
  return value
end

-- 转为无符号（用于持久化与十六进制展示）
function M.unsigned(color)
  local value = math.floor(tonumber(color) or 0)
  if value < 0 then
    return value + 0x100000000
  end
  return value
end

local function resolveAttr(attrId, fallback)
  local theme = activity.getTheme()
  local value = TypedValue()
  local found = theme.resolveAttribute(attrId, value, true)
  if not found then return fallback end
  if value.type >= TypedValue.TYPE_FIRST_COLOR_INT and value.type <= TypedValue.TYPE_LAST_COLOR_INT then
    return value.data
  end
  return fallback
end

local cachedRole = nil

-- 读取 MD3 颜色角色；失败时回退到 themeUtil 的结构化字段
function M.colors()
  if cachedRole ~= nil then return cachedRole end
  local t = activity.themeUtil
  local MaterialAttr = luajava.bindClass("com.google.android.material.R$attr")

  local function fromAttr(name, fallback)
    local id = MaterialAttr[name]
    if id == nil then return fallback end
    return resolveAttr(id, fallback)
  end

  local colors = {
    primary = fromAttr("colorPrimary", t.primary.main),
    onPrimary = fromAttr("colorOnPrimary", t.primary.on),
    primaryContainer = fromAttr("colorPrimaryContainer", t.primary.container),
    onPrimaryContainer = fromAttr("colorOnPrimaryContainer", t.primary.onContainer),
    secondary = fromAttr("colorSecondary", t.secondary.main),
    onSecondary = fromAttr("colorOnSecondary", t.secondary.on),
    secondaryContainer = fromAttr("colorSecondaryContainer", t.secondary.container),
    onSecondaryContainer = fromAttr("colorOnSecondaryContainer", t.secondary.onContainer),
    tertiary = fromAttr("colorTertiary", t.tertiary.main),
    tertiaryContainer = fromAttr("colorTertiaryContainer", t.tertiary.container),
    onTertiaryContainer = fromAttr("colorOnTertiaryContainer", t.tertiary.onContainer),
    surface = fromAttr("colorSurface", t.surface.main),
    onSurface = fromAttr("colorOnSurface", t.surface.on),
    surfaceVariant = fromAttr("colorSurfaceVariant", t.surface.variant),
    onSurfaceVariant = fromAttr("colorOnSurfaceVariant", t.surface.onVariant),
    surfaceContainerLowest = fromAttr("colorSurfaceContainerLowest", t.surface.containerLowest),
    surfaceContainerLow = fromAttr("colorSurfaceContainerLow", t.surface.containerLow),
    surfaceContainer = fromAttr("colorSurfaceContainer", t.surface.container),
    surfaceContainerHigh = fromAttr("colorSurfaceContainerHigh", t.surface.containerHigh),
    surfaceContainerHighest = fromAttr("colorSurfaceContainerHighest", t.surface.containerHighest),
    outline = fromAttr("colorOutline", t.outline.main),
    outlineVariant = fromAttr("colorOutlineVariant", t.outline.variant),
    error = fromAttr("colorError", t.error.main),
    onError = fromAttr("colorOnError", t.error.on),
    errorContainer = fromAttr("colorErrorContainer", t.error.container),
    onErrorContainer = fromAttr("colorOnErrorContainer", t.error.onContainer),
    inverseSurface = fromAttr("colorInverseSurface", t.surface.inverse),
    inverseOnSurface = fromAttr("colorInverseOnSurface", t.surface.onInverse),
  }
  cachedRole = colors
  return colors
end

function M.resetCache()
  cachedRole = nil
end

-- ===== 深浅色 =====
local MODE_KEY = "theme_mode"

function M.mode()
  local value = pref.getString(MODE_KEY, config.THEME_MODE.SYSTEM)
  if value ~= config.THEME_MODE.LIGHT and value ~= config.THEME_MODE.DARK then
    return config.THEME_MODE.SYSTEM
  end
  return value
end

local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")

-- 把持久化的模式映射为 AppCompatDelegate 常量
local function nightModeOf(mode)
  if mode == config.THEME_MODE.LIGHT then return AppCompatDelegate.MODE_NIGHT_NO end
  if mode == config.THEME_MODE.DARK then return AppCompatDelegate.MODE_NIGHT_YES end
  return AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
end

-- 应用深浅色模式，返回是否真正发生了改变。
-- 关键点：AppCompatDelegate 的初始值是 MODE_NIGHT_UNSPECIFIED(-100)，
-- 如果无条件调用 setDefaultNightMode(FOLLOW_SYSTEM)，会被判定为“值变化”
-- 并重建已注册的 Activity，表现为启动瞬间整屏闪烁。
-- 因此“跟随系统”且当前尚未指定（或已跟随）时不做任何调用。
function M.applyMode(mode, recreate)
  local target = mode or M.mode()
  pref.setString(MODE_KEY, target)
  local nightMode = nightModeOf(target)

  local ok, current = pcall(function() return AppCompatDelegate.getDefaultNightMode() end)
  if not ok then return false end

  if nightMode == AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM then
    local unspecified = AppCompatDelegate.MODE_NIGHT_UNSPECIFIED
    if current == AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
      or (unspecified ~= nil and current == unspecified) then
      return false
    end
  end

  if current == nightMode then return false end

  pcall(function() AppCompatDelegate.setDefaultNightMode(nightMode) end)
  -- 显式 recreate 仅供启动前的场景使用；交互中由 AppCompat 自动重建
  if recreate then
    pcall(function() activity.recreate() end)
  end
  return true
end

-- ===== 种子色 / 动态取色 =====
local SEED_KEY = "theme_seed"
local SEED_SOURCE_KEY = "theme_seed_source"

function M.seedSource()
  local value = pref.getString(SEED_SOURCE_KEY, config.SEED_SOURCE.SYSTEM)
  if value ~= config.SEED_SOURCE.SEED then
    return config.SEED_SOURCE.SYSTEM
  end
  return value
end

function M.seedColor()
  local stored = pref.getInt(SEED_KEY, nil)
  if stored == nil then return nil end
  return M.normalize(stored)
end

function M.applySeed()
  M.resetCache()
  local source = M.seedSource()
  local applied = false
  if source == config.SEED_SOURCE.SEED then
    local seed = M.seedColor()
    if seed ~= nil then
      applied = pcall(function() activity.dynamicColor(seed) end)
    end
  end
  if not applied then
    -- 跟随系统壁纸取色；平台不支持时保持默认 MD3 色板
    applied = pcall(function() activity.dynamicColor() end)
  end
  M.resetCache()
  return applied
end

function M.setSeed(color)
  pref.setInt(SEED_KEY, M.unsigned(color))
  pref.setString(SEED_SOURCE_KEY, config.SEED_SOURCE.SEED)
end

function M.setFollowWallpaper()
  pref.setString(SEED_SOURCE_KEY, config.SEED_SOURCE.SYSTEM)
end

-- 应用启动时调用（必须在 setContentView 之前）
function M.bootstrap()
  M.applyMode(nil, false)
  M.applySeed()
end

-- 当前摘要，用于设置页展示
function M.summary()
  local mode = M.mode()
  local modeText = "跟随系统"
  if mode == config.THEME_MODE.LIGHT then modeText = "浅色" end
  if mode == config.THEME_MODE.DARK then modeText = "深色" end
  local source = M.seedSource()
  local seedText = "跟随壁纸"
  if source == config.SEED_SOURCE.SEED then
    local seed = M.seedColor()
    if seed ~= nil then
      seedText = string.format("#%06X", M.unsigned(seed) % 0x1000000)
    end
  end
  return modeText .. " · " .. seedText
end

return M
