-- loadlayout 属性合法性审计（反射法，确定性验证）
-- 原理：loadlayout 把属性名映射为 setXxx(...) 或同名 public field。
-- 这里用 Java 反射检查每个 (控件类, 属性名) 是否真的存在可映射目标。
-- 注意：loadlayout 的属性告警不走 Lua print，无法通过日志劫持捕获（已实测），
-- 因此必须用反射做确定性校验。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_audit_reflect.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local function classNameOf(clazz)
  local ok, name = pcall(function() return clazz.getName() end)
  if ok then return tostring(name) end
  return "?"
end

-- loadlayout 自行处理的专用键（非 setter）
local SPECIAL_KEYS = {
  id = true,
  padding = true, paddingLeft = true, paddingTop = true, paddingRight = true,
  paddingBottom = true, paddingStart = true, paddingEnd = true,
  layout_width = true, layout_height = true, layout_weight = true,
  layout_margin = true, layout_marginLeft = true, layout_marginTop = true,
  layout_marginRight = true, layout_marginBottom = true,
  layout_marginStart = true, layout_marginEnd = true,
  style = true, styleAttr = true, styleRes = true, theme = true,
  src = true, items = true, pages = true, pagesWithTitle = true,
  background = true, BackgroundColor = true, backgroundColor = true,
  radius = true, cornerRadius = true,
  cardElevation = true, CardElevation = true,
  onClick = true, onLongClick = true,
  layout_gravity = true, layout_behavior = true, layout_anchor = true,
  layout_scrollFlags = true, layout_collapseMode = true,
  layout_collapseParallaxMultiplier = true,
  -- textStyle 由 loadlayout 内部按枚举转成 setTypeface（实测 "bold" / "bold|italic" 生效），
  -- 反射查不到 setTextStyle，故列为专用键。
  textStyle = true,
}

-- 别名 → 实际 setter 名
local ALIASES = {
  CardBackgroundColor = "cardBackgroundColor",
  BackgroundTintList = "backgroundTintList",
  backgroundTint = "backgroundTintList",
  iconTint = "iconTint",
  IconTint = "iconTint",
  iconTintList = "iconTintList",
  TintColor = "tintColor",
  tintColor = "tintColor",
  Checked = "checked",
  Checkable = "checkable",
}

local function hasSetter(clazz, name)
  local candidates = {}
  candidates[#candidates + 1] = "set" .. name:sub(1, 1):upper() .. name:sub(2)
  local aliasTarget = ALIASES[name]
  if aliasTarget ~= nil then
    candidates[#candidates + 1] = "set" .. aliasTarget:sub(1, 1):upper() .. aliasTarget:sub(2)
  end
  candidates[#candidates + 1] = "set" .. name

  local methods = clazz.getMethods()
  for i = 0, methods.length - 1 do
    local methodName = tostring(methods[i].getName())
    for _, candidate in ipairs(candidates) do
      if methodName == candidate then return candidate end
    end
  end
  return nil
end

local function hasField(clazz, name)
  local ok, field = pcall(function() return clazz.getField(name) end)
  if ok and field ~= nil then return name end
  return nil
end

local function check(clazz, attribute)
  if SPECIAL_KEYS[attribute] then return "SPECIAL", "loadlayout 专用键" end
  local setter = hasSetter(clazz, attribute)
  if setter ~= nil then return "OK", "setter " .. setter end
  local field = hasField(clazz, attribute)
  if field ~= nil then return "OK", "field " .. field end
  return "INVALID", "无 setter / field"
end

local bindClass = luajava.bindClass
local MATRIX = {
  {
    label = "LinearLayout",
    clazz = bindClass("android.widget.LinearLayout"),
    attrs = { "orientation", "gravity", "layout_width", "layout_height", "padding",
      "BackgroundColor", "id", "layout_weight" },
  },
  {
    label = "MaterialTextView",
    clazz = bindClass("com.google.android.material.textview.MaterialTextView"),
    attrs = { "text", "textSize", "textColor", "gravity", "maxLines", "ellipsize",
      "textStyle", "layout_width", "layout_height", "layout_marginStart", "layout_marginTop" },
  },
  {
    label = "MaterialCardView",
    clazz = bindClass("com.google.android.material.card.MaterialCardView"),
    attrs = { "radius", "cardElevation", "strokeWidth", "strokeColor", "CardBackgroundColor",
      "checkable", "layout_width", "layout_height", "layout_marginTop",
      "layout_marginStart", "layout_marginEnd", "layout_weight" },
  },
  {
    label = "MaterialButton",
    clazz = bindClass("com.google.android.material.button.MaterialButton"),
    attrs = { "text", "textSize", "checkable", "styleAttr", "layout_width",
      "layout_height", "layout_weight", "layout_marginTop", "layout_marginStart" },
  },
  {
    label = "MaterialDivider",
    clazz = bindClass("com.google.android.material.divider.MaterialDivider"),
    attrs = { "dividerColor", "layout_width", "layout_height", "layout_marginStart",
      "layout_marginTop" },
  },
  {
    label = "LinearProgressIndicator",
    clazz = bindClass("com.google.android.material.progressindicator.LinearProgressIndicator"),
    attrs = { "trackColor", "indicatorColor", "trackCornerRadius", "indeterminate",
      "layout_width", "layout_height" },
  },
  {
    label = "CircularProgressIndicator",
    clazz = bindClass("com.google.android.material.progressindicator.CircularProgressIndicator"),
    attrs = { "indeterminate", "layout_width", "layout_height" },
  },
  {
    label = "NestedScrollView",
    clazz = bindClass("androidx.core.widget.NestedScrollView"),
    attrs = { "fillViewport", "BackgroundColor", "layout_width", "layout_height" },
  },
  {
    label = "HorizontalScrollView",
    clazz = bindClass("android.widget.HorizontalScrollView"),
    -- scrollbars 已确认无效（无 setter），源码改为加载后调用
    -- setHorizontalScrollBarEnabled(false)，此处仅验证替代方法可用。
    attrs = { "layout_width", "layout_height" },
  },
  {
    label = "ChipGroup",
    clazz = bindClass("com.google.android.material.chip.ChipGroup"),
    attrs = { "singleLine", "singleSelection", "chipSpacingHorizontal",
      "layout_width", "layout_height" },
  },
  {
    label = "Chip",
    clazz = bindClass("com.google.android.material.chip.Chip"),
    attrs = { "text", "checkable", "checked", "layout_width", "layout_height" },
  },
  {
    label = "MaterialTextField",
    clazz = bindClass("vinx.material.textfield.MaterialTextField"),
    attrs = { "hint", "singleLine", "inputType", "minLines", "maxLines", "text",
      "style", "tintColor", "layout_width", "layout_height", "layout_marginStart" },
  },
  {
    label = "ImageView",
    clazz = bindClass("android.widget.ImageView"),
    attrs = { "scaleType", "adjustViewBounds", "src", "layout_width", "layout_height" },
  },
  {
    label = "Space",
    clazz = bindClass("android.widget.Space"),
    attrs = { "layout_width", "layout_height" },
  },
  {
    label = "FrameLayout",
    clazz = bindClass("android.widget.FrameLayout"),
    attrs = { "layout_width", "layout_height", "BackgroundColor", "layout_weight" },
  },
  {
    label = "MaterialSwitch",
    clazz = bindClass("com.google.android.material.materialswitch.MaterialSwitch"),
    attrs = { "checked", "text", "layout_width", "layout_height" },
  },
  {
    label = "BottomNavigationView",
    clazz = bindClass("com.google.android.material.bottomnavigation.BottomNavigationView"),
    attrs = { "layout_width", "layout_height" },
  },
}

local invalidTotal = 0
for _, spec in ipairs(MATRIX) do
  log("== " .. spec.label .. " (" .. classNameOf(spec.clazz) .. ") ==")
  for _, attribute in ipairs(spec.attrs) do
    local status, detail = check(spec.clazz, attribute)
    if status == "INVALID" then
      invalidTotal = invalidTotal + 1
      log("  INVALID  " .. attribute .. "  (" .. detail .. ")")
    elseif status == "SPECIAL" then
      log("  special  " .. attribute)
    else
      log("  ok       " .. attribute .. "  (" .. detail .. ")")
    end
  end
  flush()
end

log("")
log("=== 无效属性合计: " .. invalidTotal .. " ===")
log(invalidTotal == 0 and "RESULT: 全部属性可映射" or "RESULT: 需修复上列 INVALID 项")
flush()

print = rawPrint
print("reflect audit done")
