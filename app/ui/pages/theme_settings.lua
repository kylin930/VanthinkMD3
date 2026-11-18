-- 主题设置：深浅色模式、动态取色（跟随壁纸 / 自定义种子色）、自定义色值输入。
-- 修改后立即重启当前 Activity 以应用新色板（MD3 动态色只能在 setContentView 前生效）。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local config = require "app.config"
local validator = require "app.utils.validator"

local M = {}

local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
local View = luajava.bindClass("android.view.View")

local function segment(label, current, options, onSelect, colors)
  local row = kit.row({}, { width = "match", paddingStart = 16, paddingEnd = 16 })
  local ChipGroup = luajava.bindClass("com.google.android.material.chip.ChipGroup")
  local Chip = luajava.bindClass("com.google.android.material.chip.Chip")
  local holder = loadlayout({
    ChipGroup,
    layout_width = "wrap",
    layout_height = "wrap",
    singleLine = true,
    singleSelection = true,
    chipSpacingHorizontal = "8dp",
  })
  for _, option in ipairs(options) do
    local chip = Chip(activity)
    chip.setText(option.label)
    chip.setCheckable(true)
    chip.setChecked(option.value == current)
    chip.setOnClickListener(function()
      onSelect(option.value)
    end)
    holder.addView(chip)
  end
  row.addView(holder)
  return row
end

function M.create()
  local colors = theme.colors()
  local shell = kit.scrollPage({})
  local sub = router.subPage({ title = "主题设置", content = shell.root })

  local page = { key = "theme_settings", view = sub.root }

  local function restartUi()
    -- dynamicColor 只在 setContentView 之前生效，切换种子色必须重建 Activity
    dialogs.snackbar("正在应用主题…")
    activity.delay(200, function()
      pcall(function() activity.recreate() end)
    end)
  end

  local function applyDarkMode(value)
    -- setDefaultNightMode 在值变化时会由 AppCompat 自动重建 Activity，
    -- 这里不再额外调用 recreate，避免连续重建导致界面闪烁两次。
    local changed = theme.applyMode(value, false)
    if not changed then
      dialogs.snackbar("当前已是该模式")
    end
  end

  local function render()
    shell.clear()

    shell.add(kit.sectionTitle("深色模式"))
    shell.add(kit.text("跟随系统会使用 Android 的深浅色设置", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      marginStart = 20,
      marginBottom = 8,
    }))
    shell.add(segment("dark", theme.mode(), {
      { label = "跟随系统", value = config.THEME_MODE.SYSTEM },
      { label = "浅色", value = config.THEME_MODE.LIGHT },
      { label = "深色", value = config.THEME_MODE.DARK },
    }, function(value)
      applyDarkMode(value)
    end, colors))

    shell.add(kit.sectionTitle("动态取色"))
    shell.add(kit.text("Android 12 及以上支持根据壁纸生成整套 MD3 配色", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      marginStart = 20,
      marginBottom = 8,
      maxLines = 3,
    }))
    shell.add(segment("seed", theme.seedSource(), {
      { label = "跟随壁纸", value = config.SEED_SOURCE.SYSTEM },
      { label = "自定义主题色", value = config.SEED_SOURCE.SEED },
    }, function(value)
      if value == config.SEED_SOURCE.SYSTEM then
        theme.setFollowWallpaper()
        restartUi()
      else
        local seed = theme.seedColor()
        if seed == nil then theme.setSeed(0xFF0061A4) end
        render()
        dialogs.snackbar("请选择一个主题色")
      end
    end, colors))

    shell.add(kit.sectionTitle("预设主题色"))
    local rowHolder = kit.row({}, { width = "match", paddingStart = 16, paddingEnd = 16 })
    local wrap = loadlayout({
      luajava.bindClass("android.widget.LinearLayout"),
      orientation = "horizontal",
      layout_width = "match",
      layout_height = "wrap",
    })
    for _, preset in ipairs(config.SEED_PRESETS) do
      local holder = kit.column({
        kit.colorDot(44, preset.color),
        kit.spacer(6),
        kit.text(preset.label, {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
          gravity = "center",
          width = "match",
        }),
      }, { width = "wrap", padding = 6 })
      holder.setClickable(true)
      holder.setFocusable(true)
      holder.setOnClickListener(function()
        theme.setSeed(preset.color)
        restartUi()
      end)
      wrap.addView(holder)
    end
    rowHolder.addView(wrap)
    shell.add(rowHolder)

    shell.add(kit.sectionTitle("自定义主题色"))
    local colorInput = kit.textInput({
      hint = "十六进制颜色，例如 0061A4",
      inputType = "text",
      textSize = 16,
      marginStart = 16,
      marginEnd = 16,
    })
    local currentSeed = theme.seedColor()
    if currentSeed ~= nil then
      colorInput.setText(validator.colorToHex(currentSeed))
    end
    shell.add(colorInput.root)
    shell.add(kit.spacer(10))
    shell.add(kit.row({
      kit.button("应用这个颜色", {
        style = "outlined",
        height = "44dp",
        size = kit.TYPOGRAPHY.label,
        onClick = function()
          local parsed = validator.parseColor(colorInput.getText())
          if parsed == nil then
            dialogs.snackbar("请输入 6 位十六进制颜色值")
            return
          end
          theme.setSeed(parsed)
          restartUi()
        end,
      }),
    }, { width = "match", paddingStart = 16, paddingEnd = 16 }))

    shell.add(kit.spacer(20))
    shell.add(kit.card({
      kit.row({
        kit.icon("info", 20, colors.primary),
        kit.text(
          "注意：Android 12 / 12L / 13 上 Material 库对种子色存在限制，可能回退为跟随壁纸取色；"
          .. "所选颜色会被保存，升级系统版本后自动生效。",
          {
            size = kit.TYPOGRAPHY.label,
            color = colors.onSurfaceVariant,
            width = "0dp",
            marginStart = 12,
          }),
      }, { width = "match" }),
    }, { marginHorizontal = 16, padding = 16 }))
    shell.add(kit.spacer(24))
  end

  page.render = render
  page.onShow = render
  render()
  return page
end

return M
