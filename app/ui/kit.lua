-- UI 基础构件：排版、卡片、列表项、按钮、加载/空/错误状态、滚动页容器。
-- 所有视图通过 loadlayout 创建原生 View，颜色与尺寸统一取自 theme。

local theme = require "app.ui.theme"
local icons = require "app.ui.icons"

local M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
local Space = luajava.bindClass("android.widget.Space")
local ImageView = luajava.bindClass("android.widget.ImageView")
local ScrollView = luajava.bindClass("androidx.core.widget.NestedScrollView")
local SwipeRefreshLayout = luajava.bindClass("androidx.swiperefreshlayout.widget.SwipeRefreshLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
local MaterialDivider = luajava.bindClass("com.google.android.material.divider.MaterialDivider")
local LinearProgress = luajava.bindClass("com.google.android.material.progressindicator.LinearProgressIndicator")
local CircularProgress = luajava.bindClass("com.google.android.material.progressindicator.CircularProgressIndicator")
local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
local ViewGroupLayoutParams = luajava.bindClass("android.view.ViewGroup$LayoutParams")
local LinearLayoutParams = luajava.bindClass("android.widget.LinearLayout$LayoutParams")
local Gravity = luajava.bindClass("android.view.Gravity")
local AppCompatEditText = luajava.bindClass("androidx.appcompat.widget.AppCompatEditText")

M.TYPOGRAPHY = {
  display = 26,
  headline = 20,
  title = 16,
  body = 14,
  label = 12,
}

-- 窄屏阈值：低于该宽度（dp）双列布局会被挤压成零宽，需要退化为单列
M.COMPACT_WIDTH_DP = 360

-- 统一间距规范（单位 dp）。所有页面统一从这里取值，不再各自写魔法数字。
-- pageHorizontal 是页面的左右视觉基线：卡片边缘、列表项图标、分组标题都对齐这条线；
-- 列表项正文列按 MD3 keyline 落在 pageHorizontal + listIcon + listIconGap = 56dp。
M.SPACING = {
  pageHorizontal = 16,
  sectionTop = 20,
  sectionBottom = 8,
  cardGap = 12,
  groupGap = 10,
  cardPadding = 16,
  pageBottom = 16,
  listIcon = 24,
  listIconGap = 16,
}

local function load(spec)
  return loadlayout(spec)
end

M.load = load

-- ===== 尺寸与 LayoutParams =====
-- 关键点：独立 loadlayout 出来的根视图，其 LayoutParams 类型由控件自身决定
-- （FrameLayout → FrameLayout.LayoutParams，MaterialCardView → FrameLayout.LayoutParams）。
-- 这类 LayoutParams 没有 weight 字段，因此「layout_height = "0dp" + layout_weight = N」
-- 的写法在根视图上**完全无效**：高度变成 0，视图被压扁不可见。
-- 需要 weight 时必须在加入父容器前显式换成 LinearLayout.LayoutParams。
local function sizeToPx(value)
  if value == nil then return ViewGroupLayoutParams.WRAP_CONTENT end
  if type(value) == "number" then return value end
  local text = tostring(value)
  if text == "match" or text == "fill" then return ViewGroupLayoutParams.MATCH_PARENT end
  if text == "wrap" then return ViewGroupLayoutParams.WRAP_CONTENT end
  local dpValue = string.match(text, "^(%d+)dp$")
  if dpValue ~= nil then return theme.dp(tonumber(dpValue)) end
  local percent = string.match(text, "^(%d+)%%$")
  if percent ~= nil then return ViewGroupLayoutParams.MATCH_PARENT end
  local number = tonumber(text)
  if number ~= nil then return math.floor(number) end
  return ViewGroupLayoutParams.WRAP_CONTENT
end

-- 边距数值一律按 dp 解释（"16dp" 与 16 都表示 16dp）。
-- 早期版本把裸数字直接当像素：marginHorizontal = 16 实际只有 5.3dp，
-- 实机上看起来就是「卡片贴边、间距没生效」。
local function marginToPx(value)
  if value == nil then return 0 end
  if type(value) == "number" then return theme.dp(value) end
  return sizeToPx(value)
end

-- 把视图的 LayoutParams 换成带 weight 的 LinearLayout.LayoutParams
-- opts: width / height / weight / marginTop / marginBottom / marginStart / marginEnd
-- 注意：width / height 走 sizeToPx（数字按像素），margin* 走 marginToPx（数字按 dp）。
function M.applyLinearParams(view, opts)
  if view == nil then return view end
  local o = opts or {}
  local ok = pcall(function()
    local params = LinearLayoutParams(sizeToPx(o.width or "match"), sizeToPx(o.height or "wrap"))
    if o.weight ~= nil then params.weight = o.weight end
    params.setMargins(marginToPx(o.marginStart), marginToPx(o.marginTop),
      marginToPx(o.marginEnd), marginToPx(o.marginBottom))
    view.setLayoutParams(params)
  end)
  return ok and view or view
end

-- 显式应用外边距。
-- 原因：独立 loadlayout 出来的根视图拿到的 LayoutParams 是 android.view.ViewGroup$LayoutParams，
-- 该类型**没有边距字段**，写在 spec 里的 layout_marginStart / layout_marginTop 会被静默丢弃。
-- 实机实测：kit.card({...}, { marginHorizontal = 16 }) 加入竖向 LinearLayout 后 leftMargin 仍为 0，
-- 卡片直接贴屏幕边缘。这里把边距写进 LinearLayout.LayoutParams，并保留原有宽高与权重。
-- 可以直接用 LinearLayout.LayoutParams：kit 的 column / row / scrollPage / card 内部的父容器
-- 都是 LinearLayout，addView 时会复用这份参数（含边距与 weight）。
-- opts: horizontal / start / end / top / bottom（数值按 dp 处理，也接受 "16dp"）
function M.applyMargins(view, opts)
  if view == nil then return view end
  local o = opts or {}
  local startMargin = o.start or o.horizontal or o.marginStart or 0
  local endMargin = o["end"] or o.horizontal or o.marginEnd or 0
  local topMargin = o.top or o.marginTop or 0
  local bottomMargin = o.bottom or o.marginBottom or 0
  if startMargin == 0 and endMargin == 0 and topMargin == 0 and bottomMargin == 0 then
    return view
  end
  pcall(function()
    local current = view.getLayoutParams()
    local width = ViewGroupLayoutParams.WRAP_CONTENT
    local height = ViewGroupLayoutParams.WRAP_CONTENT
    local weight = 0
    if current ~= nil then
      if current.width ~= nil then width = current.width end
      if current.height ~= nil then height = current.height end
      local okWeight, value = pcall(function() return current.weight end)
      if okWeight and type(value) == "number" then weight = value end
    end
    local params = LinearLayoutParams(width, height, weight)
    params.setMargins(marginToPx(startMargin), marginToPx(topMargin),
      marginToPx(endMargin), marginToPx(bottomMargin))
    view.setLayoutParams(params)
  end)
  return view
end

-- 给可点击容器套上系统 Ripple（?attr/selectableItemBackground）。
-- 不使用自定义 drawable：原生 ripple 自带按下反馈、无障碍与主题着色。
function M.ripple(view)
  if view == nil then return view end
  pcall(function()
    local TypedValue = luajava.bindClass("android.util.TypedValue")
    local attr = luajava.bindClass("android.R$attr").selectableItemBackground
    local value = TypedValue()
    if activity.getTheme().resolveAttribute(attr, value, true) and value.resourceId ~= 0 then
      view.setBackgroundResource(value.resourceId)
    end
  end)
  return view
end

-- ===== 排版 =====
function M.text(content, opts)
  local o = opts or {}
  local colors = theme.colors()
  local spec = {
    MaterialTextView,
    layout_width = o.width or "wrap",
    layout_height = o.height or "wrap",
    text = tostring(content or ""),
    textSize = tostring(o.size or M.TYPOGRAPHY.body) .. "sp",
    textColor = o.color or colors.onSurface,
    gravity = o.gravity or "start|center_vertical",
  }
  if o.maxLines then
    spec.maxLines = o.maxLines
    spec.ellipsize = "end"
  end
  if o.bold then spec.textStyle = "bold" end
  local view = load(spec)
  -- width = "0dp" 只有在父容器分配了 weight 时才有意义。
  -- 漏写 weight 的调用会让宽度恒为 0，文字整体不可见，
  -- 因此这里统一兜底：显式 weight 优先，否则 0dp 视为 weight = 1。
  local weight = o.weight
  if weight == nil and o.width == "0dp" then weight = 1 end
  if weight ~= nil then
    M.applyLinearParams(view, {
      width = o.width or "0dp",
      height = o.height or "wrap",
      weight = weight,
      marginTop = o.marginTop,
      marginBottom = o.marginBottom,
      marginStart = o.marginStart,
      marginEnd = o.marginEnd,
    })
  else
    -- 无 weight 的文本同样需要显式边距：loadlayout 根视图的 spec 边距不会生效
    M.applyMargins(view, {
      start = o.marginStart,
      top = o.marginTop,
      bottom = o.marginBottom,
      ["end"] = o.marginEnd,
    })
  end
  return view
end

-- ===== 间距 =====
-- 纵向间距：宽度 match，只能放进竖向 LinearLayout。
-- 放进横向行会吃掉整行剩余宽度，把后面的内容挤出屏幕（横向间距请用 hSpacer）。
function M.spacer(heightDp)
  return load({
    Space,
    layout_width = "match",
    layout_height = tostring(heightDp) .. "dp",
  })
end

-- 横向间距：固定宽度、高度 wrap（自身高度为 0，不影响父容器高度测量）。
-- 只能放进横向 LinearLayout。
function M.hSpacer(widthDp)
  return load({
    Space,
    layout_width = tostring(math.floor(widthDp or 8)) .. "dp",
    layout_height = "wrap",
  })
end

-- 当前窗口宽度（dp）。用 configuration.screenWidthDp，不受字体缩放影响。
function M.windowWidthDp()
  local ok, value = pcall(function()
    return activity.getResources().getConfiguration().screenWidthDp
  end)
  if ok and type(value) == "number" and value > 0 then return value end
  local okMetrics, width = pcall(function()
    local metrics = activity.getResources().getDisplayMetrics()
    return metrics.widthPixels / metrics.density
  end)
  if okMetrics and type(width) == "number" and width > 0 then return width end
  return 360
end

-- 窄屏判定：双列 / 横向排列的内容在该宽度以下需要退化为单列
function M.isCompactWidth()
  return M.windowWidthDp() < M.COMPACT_WIDTH_DP
end

function M.divider(marginTop, marginBottom)
  local colors = theme.colors()
  local view = load({
    MaterialDivider,
    layout_width = "match",
    layout_height = "1dp",
    dividerColor = colors.outlineVariant,
  })
  M.applyMargins(view, { top = marginTop or 0, bottom = marginBottom or 0 })
  return view
end

-- ===== 布局容器 =====
-- weight 仅在同一父 LinearLayout 内生效，水平方向需显式 width = "0dp"。
-- 根视图的默认 LayoutParams 不含 weight，故有 weight 时必须显式换成
-- LinearLayout.LayoutParams（见 applyLinearParams）。
function M.column(children, opts)
  local o = opts or {}
  local spec = {
    LinearLayout,
    orientation = "vertical",
    layout_width = o.width or "match",
    layout_height = o.height or "wrap",
  }
  if o.weight then spec.layout_weight = o.weight end
  if o.padding then spec.padding = o.padding .. "dp" end
  if o.paddingStart then spec.paddingStart = o.paddingStart .. "dp" end
  if o.paddingEnd then spec.paddingEnd = o.paddingEnd .. "dp" end
  if o.paddingTop then spec.paddingTop = o.paddingTop .. "dp" end
  if o.paddingBottom then spec.paddingBottom = o.paddingBottom .. "dp" end
  if o.gravity then spec.gravity = o.gravity end
  if o.background then spec.BackgroundColor = o.background end
  if o.id then spec.id = o.id end
  for _, child in ipairs(children or {}) do
    if child ~= nil then spec[#spec + 1] = child end
  end
  local view = load(spec)
  if o.weight ~= nil then
    M.applyLinearParams(view, {
      width = o.width, height = o.height, weight = o.weight,
      marginTop = o.marginTop, marginBottom = o.marginBottom,
      marginStart = o.marginStart, marginEnd = o.marginEnd,
    })
  else
    M.applyMargins(view, {
      start = o.marginStart, top = o.marginTop,
      bottom = o.marginBottom, ["end"] = o.marginEnd,
    })
  end
  return view
end

function M.row(children, opts)
  local o = opts or {}
  local spec = {
    LinearLayout,
    orientation = "horizontal",
    layout_width = o.width or "match",
    layout_height = o.height or "wrap",
    gravity = o.gravity or "start|center_vertical",
  }
  if o.weight then spec.layout_weight = o.weight end
  if o.padding then spec.padding = o.padding .. "dp" end
  if o.paddingStart then spec.paddingStart = o.paddingStart .. "dp" end
  if o.paddingEnd then spec.paddingEnd = o.paddingEnd .. "dp" end
  if o.paddingTop then spec.paddingTop = o.paddingTop .. "dp" end
  if o.paddingBottom then spec.paddingBottom = o.paddingBottom .. "dp" end
  if o.background then spec.BackgroundColor = o.background end
  if o.id then spec.id = o.id end
  for _, child in ipairs(children or {}) do
    if child ~= nil then spec[#spec + 1] = child end
  end
  local view = load(spec)
  if o.weight ~= nil then
    M.applyLinearParams(view, {
      width = o.width, height = o.height, weight = o.weight,
      marginTop = o.marginTop, marginBottom = o.marginBottom,
      marginStart = o.marginStart, marginEnd = o.marginEnd,
    })
  else
    M.applyMargins(view, {
      start = o.marginStart, top = o.marginTop,
      bottom = o.marginBottom, ["end"] = o.marginEnd,
    })
  end
  return view
end

-- ===== 图标 =====
function M.icon(name, sizeDp, color)
  local colors = theme.colors()
  local size = sizeDp or 22
  local drawable = icons.get(name, size, color or colors.onSurfaceVariant)
  local view = load({
    ImageView,
    layout_width = size .. "dp",
    layout_height = size .. "dp",
    scaleType = "fitCenter",
  })
  if drawable ~= nil then view.setImageDrawable(drawable) end
  return view
end

-- 用于在 FrameLayout 中居中的 LayoutParams
function M.centeredParams()
  local params = load({
    FrameLayout,
    layout_width = "wrap",
    layout_height = "wrap",
  }).getLayoutParams()
  params.gravity = Gravity.CENTER
  return params
end

-- 圆形色块（主题色预览、头像占位）
function M.colorDot(sizeDp, color, ringColor)
  local view = load({
    FrameLayout,
    layout_width = sizeDp .. "dp",
    layout_height = sizeDp .. "dp",
  })
  local ok = pcall(function()
    local drawable = GradientDrawable()
    drawable.setShape(GradientDrawable.OVAL)
    drawable.setColor(theme.normalize(color))
    if ringColor ~= nil then
      drawable.setStroke(theme.dp(2), theme.normalize(ringColor))
    end
    view.setBackground(drawable)
  end)
  if not ok then view.setBackgroundColor(theme.normalize(color)) end
  return view
end

-- 圆角矩形背景容器
function M.pill(child, opts)
  local o = opts or {}
  local colors = theme.colors()
  local container = load({
    FrameLayout,
    layout_width = "wrap",
    layout_height = "wrap",
    paddingStart = (o.paddingHorizontal or 10) .. "dp",
    paddingEnd = (o.paddingHorizontal or 10) .. "dp",
    paddingTop = (o.paddingVertical or 4) .. "dp",
    paddingBottom = (o.paddingVertical or 4) .. "dp",
  })
  local ok = pcall(function()
    local drawable = GradientDrawable()
    drawable.setShape(GradientDrawable.RECTANGLE)
    drawable.setCornerRadius(theme.dp(o.radius or 100))
    drawable.setColor(theme.normalize(o.background or colors.secondaryContainer))
    if o.strokeColor ~= nil then
      drawable.setStroke(theme.dp(1), theme.normalize(o.strokeColor))
    end
    container.setBackground(drawable)
  end)
  if not ok then
    container.setBackgroundColor(theme.normalize(o.background or colors.secondaryContainer))
  end
  if child ~= nil then container.addView(child) end
  return container
end

-- 文本标签（轻量徽标，不使用 Chip 以降低交互开销）
function M.badge(label, opts)
  local o = opts or {}
  local colors = theme.colors()
  local text = M.text(label, {
    size = o.size or M.TYPOGRAPHY.label,
    color = o.color or colors.onSecondaryContainer,
    gravity = "center",
    bold = o.bold,
  })
  return M.pill(text, {
    background = o.background or colors.secondaryContainer,
    paddingHorizontal = o.paddingHorizontal or 10,
    paddingVertical = o.paddingVertical or 4,
    strokeColor = o.strokeColor,
  })
end

-- ===== 卡片 =====
function M.card(children, opts)
  local o = opts or {}
  local colors = theme.colors()
  local spec = {
    MaterialCardView,
    layout_width = o.width or "match",
    layout_height = o.height or "wrap",
    radius = (o.radius or 20) .. "dp",
    cardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = o.strokeColor or colors.outlineVariant,
    CardBackgroundColor = o.background or colors.surfaceContainerLow,
    checkable = false,
  }
  if o.id then spec.id = o.id end

  local inner = M.column(children or {}, {
    width = "match",
    height = "wrap",
    padding = o.padding or M.SPACING.cardPadding,
  })
  spec[#spec + 1] = inner
  local card = load(spec)
  -- 根卡片的 spec 边距不会生效（见 applyMargins 注释），必须显式写入 LayoutParams：
  -- weight 与边距都要在加入父容器**之前**设置好，否则外侧的 marginHorizontal 会被丢掉，
  -- 卡片就会贴着屏幕边缘。
  local marginStart = o.marginHorizontal or o.marginStart
  local marginEnd = o.marginHorizontal or o.marginEnd
  if o.weight ~= nil then
    M.applyLinearParams(card, {
      width = o.width or "match",
      height = o.height or "wrap",
      weight = o.weight,
      marginTop = o.marginTop,
      marginBottom = o.marginBottom,
      marginStart = marginStart,
      marginEnd = marginEnd,
    })
  else
    M.applyMargins(card, {
      start = marginStart,
      top = o.marginTop,
      bottom = o.marginBottom,
      ["end"] = marginEnd,
    })
  end
  if o.onClick ~= nil then
    card.setClickable(true)
    card.setFocusable(true)
    card.setOnClickListener(function(view) o.onClick(view) end)
  end
  return card
end

-- ===== 按钮 =====
function M.button(label, opts)
  local o = opts or {}
  local colors = theme.colors()
  -- 高度用「最小高度」而不是固定 layout_height：
  -- 固定高度在字体放大（例如系统字体 1.3 倍）时会把文字上下裁掉，
  -- 而 MaterialButton 自带的 insetTop/insetBottom 还会再吃掉 12dp。
  -- 改成 wrap + setMinimumHeight 后，1.0 倍字体时高度与设计一致，
  -- 放大字体时按钮自然长高，文字不会被裁切，触控高度也始终不小于 48dp。
  local minHeight = o.height or "48dp"
  local spec = {
    MaterialButton,
    layout_width = o.width or "wrap",
    layout_height = "wrap",
    text = label,
    textSize = (o.size or M.TYPOGRAPHY.body) .. "sp",
    checkable = false,
  }
  if o.style == "outlined" then
    spec.styleAttr = "?attr/materialButtonOutlinedStyle"
  elseif o.style == "text" then
    spec.styleAttr = "?attr/borderlessButtonStyle"
  end
  if o.weight then spec.layout_weight = o.weight end
  local button = load(spec)
  pcall(function()
    local px = sizeToPx(minHeight)
    button.setMinimumHeight(px)
    button.setMinHeight(px)
  end)
  M.applyMargins(button, {
    start = o.marginStart, top = o.marginTop,
    bottom = o.marginBottom, ["end"] = o.marginEnd,
  })
  if o.iconName then
    local tint = o.iconColor
      or ((o.style == nil or o.style == "filled") and colors.onPrimary or colors.primary)
    local ok = pcall(function()
      local drawable = icons.get(o.iconName, 18, tint)
      if drawable ~= nil then button.setIcon(drawable) end
      button.setIconGravity(2)
      button.setIconPadding(theme.dp(8))
    end)
    if not ok then button.setText(label) end
  end
  if o.onClick ~= nil then
    button.setOnClickListener(function(view) o.onClick(view) end)
  end
  return button
end

function M.iconButton(iconName, opts)
  local o = opts or {}
  local colors = theme.colors()
  local size = o.size or 44
  local button = load({
    MaterialButton,
    layout_width = size .. "dp",
    layout_height = size .. "dp",
    styleAttr = "?attr/materialIconButtonStyle",
    checkable = false,
  })
  pcall(function()
    local drawable = icons.get(iconName, o.iconSize or 22, o.color or colors.onSurfaceVariant)
    if drawable ~= nil then
      button.setIcon(drawable)
      button.setIconSize(theme.dp(o.iconSize or 22))
    end
  end)
  if o.onClick ~= nil then
    button.setOnClickListener(function(view) o.onClick(view) end)
  end
  return button
end

-- ===== 列表项 =====
-- MD3 Leading Icon 布局：
--   水平内边距 16dp / 图标容器 24×24 / 图标 24dp / 图标与文字间距 16dp
--   → 正文列落在 16 + 24 + 16 = 56dp 的 MD3 列表 keyline 上。
-- 高度：单行 56dp、双行 72dp（用最小高度保证，不是固定高度），
-- 内容再多（三行以上、标题两行）时自然撑开，不会裁切文字。
-- 整行仍然是点击区域：padding 与最小高度都作用在整行容器上，
-- 缩小图标容器不会缩小触控区域。
function M.listItem(opts)
  local o = opts or {}
  local colors = theme.colors()
  local paddingHorizontal = o.paddingHorizontal or M.SPACING.pageHorizontal
  local hasSubtitle = o.subtitle ~= nil and o.subtitle ~= ""
  local container = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = paddingHorizontal .. "dp",
    paddingEnd = paddingHorizontal .. "dp",
    paddingTop = (o.paddingVertical or 12) .. "dp",
    paddingBottom = (o.paddingVertical or 12) .. "dp",
  })
  pcall(function()
    container.setMinimumHeight(theme.dp(o.minHeight or (hasSubtitle and 72 or 56)))
  end)

  if o.icon then
    local iconSize = o.iconSize or M.SPACING.listIcon
    -- 图标容器与图标同尺寸：多出来的空白只会把文字推远，MD3 的 leading icon 本身就是 24dp 网格
    local holder = load({
      FrameLayout,
      layout_width = iconSize .. "dp",
      layout_height = iconSize .. "dp",
    })
    -- 根视图的 LayoutParams 由控件自身决定，边距写在 spec 里不会被应用，
    -- 必须在加入父容器前显式换成 LinearLayout.LayoutParams。
    M.applyLinearParams(holder, {
      width = iconSize .. "dp",
      height = iconSize .. "dp",
      marginEnd = o.iconGap or M.SPACING.listIconGap,
    })
    local iconView = M.icon(o.icon, iconSize, o.iconColor or colors.primary)
    holder.addView(iconView, M.centeredParams())
    container.addView(holder)
  end

  local textHolder = load({
    LinearLayout,
    orientation = "vertical",
    layout_width = "0dp",
    layout_height = "wrap",
    gravity = "start|center_vertical",
  })
  -- 必须显式 applyLinearParams：独立 loadlayout 的根视图会丢掉 layout_weight，
  -- 只剩 width = 0dp，主标题与副标题的可用宽度都是 0，整行文字不可见。
  M.applyLinearParams(textHolder, { width = "0dp", height = "wrap", weight = 1 })
  textHolder.addView(M.text(o.title or "", {
    size = o.titleSize or 15,
    color = o.titleColor or colors.onSurface,
    maxLines = o.titleMaxLines or 2,
  }))
  if hasSubtitle then
    textHolder.addView(M.text(o.subtitle, {
      size = o.subtitleSize or 13,
      color = o.subtitleColor or colors.onSurfaceVariant,
      maxLines = o.subtitleMaxLines or 3,
      marginTop = 2,
    }))
  end
  container.addView(textHolder)

  -- 右侧附加内容固定宽度、不参与挤压：textHolder 的 weight = 1 会先让出空间
  if o.trailingText then
    container.addView(M.text(o.trailingText, {
      size = M.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      marginStart = 8,
    }))
  end
  if o.trailingView ~= nil then
    M.applyMargins(o.trailingView, { start = 8 })
    container.addView(o.trailingView)
  elseif o.trailingIcon then
    local view = M.icon(o.trailingIcon, 20, colors.onSurfaceVariant)
    M.applyMargins(view, { start = 8 })
    container.addView(view)
  elseif o.showChevron then
    local view = M.icon("chevron_right", 20, colors.outline)
    M.applyMargins(view, { start = 8 })
    container.addView(view)
  end

  if o.onClick ~= nil then
    -- 整行点击 + 原生 ripple
    M.ripple(container)
    container.setClickable(true)
    container.setFocusable(true)
    container.setOnClickListener(function(view) o.onClick(view) end)
  end
  return container
end

-- ===== 进度 =====
function M.linearProgress(indeterminate)
  local colors = theme.colors()
  local spec = {
    LinearProgress,
    layout_width = "match",
    layout_height = "wrap",
    trackColor = colors.surfaceContainerHighest,
    indicatorColor = colors.primary,
    trackCornerRadius = "4dp",
  }
  if indeterminate then spec.indeterminate = true end
  return load(spec)
end

function M.spinner(sizeDp)
  return load({
    CircularProgress,
    layout_width = (sizeDp or 28) .. "dp",
    layout_height = (sizeDp or 28) .. "dp",
    indeterminate = true,
  })
end

-- ===== 状态区块 =====
function M.stateView(opts)
  local o = opts or {}
  local colors = theme.colors()
  local children = {
    M.icon(o.icon or "inbox", 44, o.iconColor or colors.outline),
    M.spacer(14),
    M.text(o.title or "", {
      size = M.TYPOGRAPHY.title,
      color = o.titleColor or colors.onSurface,
      gravity = "center",
      width = "match",
    }),
  }
  if o.message and o.message ~= "" then
    children[#children + 1] = M.spacer(6)
    children[#children + 1] = M.text(o.message, {
      size = M.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      gravity = "center",
      width = "match",
    })
  end
  if o.actionLabel then
    children[#children + 1] = M.spacer(18)
    children[#children + 1] = M.button(o.actionLabel, {
      style = "outlined",
      height = "40dp",
      iconName = o.actionIcon,
      onClick = o.onAction,
    })
  end
  return M.column(children, {
    width = "match",
    paddingTop = 36,
    paddingBottom = 36,
    paddingStart = 32,
    paddingEnd = 32,
    gravity = "center_horizontal",
  })
end

-- ===== 输入框 =====
-- 不使用 vinx.material.textfield.MaterialTextField（TextInputLayout 封装）：
-- 实测该控件在无交互时仍以约 43 次/秒持续重绘（label 浮动动画不停），
-- 会让整个界面看起来一直在闪烁。这里用 AppCompatEditText + MaterialCardView
-- 自绘 MD3 外观的输入框：圆角、描边、聚焦变色，行为完全可控。
-- 返回 { root, edit, getText, setText, setError, clearError, setPasswordVisible, focus }
function M.textInput(opts)
  local o = opts or {}
  local colors = theme.colors()

  local spec = {
    MaterialCardView,
    layout_width = o.width or "match",
    layout_height = "wrap",
    radius = (o.radius or 12) .. "dp",
    cardElevation = 0,
    strokeWidth = "1dp",
    strokeColor = colors.outlineVariant,
    CardBackgroundColor = colors.surfaceContainerLowest,
    checkable = false,
  }
  local card = load(spec)
  -- 根视图的 spec 边距不会生效，必须显式写入 LayoutParams（同 applyMargins 注释）
  M.applyMargins(card, {
    start = o.marginStart, top = o.marginTop,
    bottom = o.marginBottom, ["end"] = o.marginEnd,
  })

  local holder = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = (o.paddingHorizontal or 14) .. "dp",
    paddingEnd = (o.paddingHorizontal or 14) .. "dp",
    paddingTop = (o.paddingVertical or 12) .. "dp",
    paddingBottom = (o.paddingVertical or 12) .. "dp",
  })
  card.addView(holder)

  local edit = AppCompatEditText(activity)
  pcall(function() edit.setBackgroundResource(android.R.color.transparent) end)
  edit.setHint(tostring(o.hint or ""))
  edit.setTextSize(o.textSize or 16)
  edit.setTextColor(theme.normalize(colors.onSurface))
  edit.setHintTextColor(theme.normalize(colors.onSurfaceVariant))

  local InputType = luajava.bindClass("android.text.InputType")
  local inputType = o.inputType or "text"
  if inputType == "phone" then
    edit.setInputType(InputType.TYPE_CLASS_PHONE)
  elseif inputType == "number" then
    edit.setInputType(InputType.TYPE_CLASS_NUMBER)
  elseif inputType == "password" then
    edit.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD)
  else
    edit.setInputType(InputType.TYPE_CLASS_TEXT)
  end

  if o.singleLine == false then
    edit.setSingleLine(false)
    pcall(function() edit.setMinLines(o.minLines or 2) end)
    pcall(function() edit.setMaxLines(o.maxLines or 6) end)
  else
    edit.setSingleLine(true)
  end

  -- 注意：这里不能借用临时 LinearLayout 的 getLayoutParams() 来取参数。
  -- 独立 loadlayout 出来的根视图拿到的 LayoutParams 里 layout_weight 会丢失，
  -- 结果编辑框宽度恒为 0dp，登录页输入框完全不可见。
  -- 必须显式构造 LinearLayout.LayoutParams 后再 addView。
  M.applyLinearParams(edit, { width = "0dp", height = "wrap", weight = 1 })
  holder.addView(edit)

  local function applyStroke(color)
    pcall(function() card.setStrokeColor(theme.normalize(color)) end)
  end

  edit.setOnFocusChangeListener(function(view, hasFocus)
    applyStroke(hasFocus and colors.primary or colors.outlineVariant)
  end)

  local api = {
    root = card,
    card = card,
    holder = holder,
    edit = edit,
    getText = function()
      local text = nil
      pcall(function() text = tostring(edit.getText()) end)
      return text or ""
    end,
    setText = function(value)
      pcall(function() edit.setText(tostring(value or "")) end)
    end,
    setError = function()
      applyStroke(colors.error)
    end,
    clearError = function()
      applyStroke(colors.outlineVariant)
    end,
    focus = function()
      pcall(function() edit.requestFocus() end)
    end,
    setPasswordVisible = function(visible)
      local mode
      if visible then
        mode = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
      else
        mode = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
      end
      pcall(function()
        local existing = tostring(edit.getText())
        edit.setInputType(mode)
        edit.setText(existing)
        edit.setSelection(#existing)
      end)
    end,
  }
  return api
end

-- ===== 滚动页容器 =====
-- 只有传入 onRefresh 时才套 SwipeRefreshLayout；
-- 否则直接用普通滚动容器，避免无意义的额外测量与下拉动画开销。
function M.scrollPage(opts)
  local o = opts or {}
  local colors = theme.colors()

  local content = load({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "wrap",
    paddingBottom = M.SPACING.pageBottom .. "dp",
  })
  local scroll = load({
    ScrollView,
    layout_width = "match",
    layout_height = "match",
    fillViewport = true,
    BackgroundColor = colors.surface,
  })
  scroll.addView(content)

  local refresh = nil
  local root = scroll

  if o.onRefresh ~= nil then
    refresh = SwipeRefreshLayout(activity)
    refresh.addView(scroll)
    root = refresh
    pcall(function()
      refresh.setColorSchemeColors({ colors.primary, colors.tertiary })
      refresh.setProgressBackgroundColorSchemeColor(colors.surfaceContainerHigh)
    end)
    refresh.setOnRefreshListener(function() o.onRefresh() end)
  end

  if o.onLoadMore ~= nil then
    -- 只有用户真正滚动（scrollY 发生变化）且接近底部时才触发分页。
    -- 早期实现只看"距离底部"，内容重排（clear/addView 改变内容高度）也会满足条件，
    -- 会导致连续加载 + 连续重绘，画面表现为闪烁。
    local lastTriggerY = -1
    local lastTriggerHeight = -1
    pcall(function()
      scroll.setOnScrollChangeListener(function(view, scrollX, scrollY, oldX, oldY)
        if scrollY == oldY then return end
        local child = view.getChildAt(0)
        if child == nil then return end
        local contentHeight = child.getMeasuredHeight()
        if contentHeight <= 0 then return end
        local remaining = contentHeight - (scrollY + view.getMeasuredHeight())
        if remaining > theme.dp(200) then return end
        if scrollY == lastTriggerY and contentHeight == lastTriggerHeight then return end
        lastTriggerY = scrollY
        lastTriggerHeight = contentHeight
        o.onLoadMore()
      end)
    end)
  end

  return {
    root = root,
    refresh = refresh,
    scroll = scroll,
    content = content,
    add = function(view) if view ~= nil then content.addView(view) end end,
    clear = function() content.removeAllViews() end,
    setRefreshing = function(value)
      if refresh == nil then return end
      pcall(function() refresh.setRefreshing(value and true or false) end)
    end,
    scrollToTop = function() pcall(function() scroll.scrollTo(0, 0) end) end,
  }
end

-- 页头：标题 + 可选副标题 + 右侧操作
function M.pageHeader(title, subtitle, actions)
  local colors = theme.colors()
  local header = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    -- 左基线用到与卡片、列表图标相同的 pageHorizontal，页头标题不会比卡片更靠右
    paddingStart = M.SPACING.pageHorizontal .. "dp",
    paddingEnd = M.SPACING.pageHorizontal .. "dp",
    paddingTop = "16dp",
    paddingBottom = "8dp",
  })
  local textHolder = load({
    LinearLayout,
    orientation = "vertical",
    layout_width = "0dp",
    layout_height = "wrap",
  })
  -- 同上：weight 必须在加入父容器前显式写入 LinearLayout.LayoutParams，
  -- 否则标题与副标题可用宽度为 0；标题也用 maxLines 兜底，避免挤压右侧操作按钮。
  M.applyLinearParams(textHolder, { width = "0dp", height = "wrap", weight = 1 })
  textHolder.addView(M.text(title, {
    size = M.TYPOGRAPHY.display,
    color = colors.onSurface,
    bold = true,
    maxLines = 2,
  }))
  if subtitle and subtitle ~= "" then
    textHolder.addView(M.text(subtitle, {
      size = M.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      maxLines = 2,
      marginTop = 4,
    }))
  end
  header.addView(textHolder)
  for _, action in ipairs(actions or {}) do header.addView(action) end
  return header
end

-- 分组标题
-- 左基线 = pageHorizontal（16dp），与卡片边缘、列表项图标左边缘对齐；
-- 上间距 sectionTop / 下间距 sectionBottom 由 SPACING 统一控制。
function M.sectionTitle(title, actionLabel, onAction)
  local colors = theme.colors()
  local row = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = M.SPACING.pageHorizontal .. "dp",
    paddingEnd = M.SPACING.pageHorizontal .. "dp",
    paddingTop = M.SPACING.sectionTop .. "dp",
    paddingBottom = M.SPACING.sectionBottom .. "dp",
  })
  local holder = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "0dp",
    layout_height = "wrap",
  })
  -- 显式 LayoutParams：否则 holder 宽度为 0，分组标题与右侧操作文字都不会显示。
  M.applyLinearParams(holder, { width = "0dp", height = "wrap", weight = 1 })
  holder.addView(M.text(title, {
    size = M.TYPOGRAPHY.label,
    color = colors.primary,
    bold = true,
    maxLines = 1,
  }))
  row.addView(holder)
  if actionLabel then
    row.addView(M.text(actionLabel, {
      size = M.TYPOGRAPHY.label,
      color = colors.primary,
    }))
    row.setClickable(true)
    row.setFocusable(true)
    row.setOnClickListener(function() if onAction then onAction() end end)
  end
  return row
end

-- 分组容器：同一组列表项放在**一张**卡片里，用 Divider 分隔（不拆成多个卡片）。
-- 分组之间的呼吸感由 groupGap（卡片下边距）保证。
function M.group(items, opts)
  local o = opts or {}
  local colors = theme.colors()
  local children = {}
  for index, item in ipairs(items) do
    if index > 1 then
      -- 分割线与列表正文列对齐（16dp 缩进）
      local divider = load({
        MaterialDivider,
        layout_width = "match",
        layout_height = "1dp",
        dividerColor = colors.outlineVariant,
      })
      M.applyMargins(divider, { start = M.SPACING.pageHorizontal })
      children[#children + 1] = divider
    end
    children[#children + 1] = item
  end
  return M.card(children, {
    padding = o.padding or 0,
    marginHorizontal = o.marginHorizontal or M.SPACING.pageHorizontal,
    marginTop = o.marginTop or 0,
    marginBottom = o.marginBottom or M.SPACING.groupGap,
  })
end

return M
