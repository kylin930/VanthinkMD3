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

-- 把视图的 LayoutParams 换成带 weight 的 LinearLayout.LayoutParams
-- opts: width / height / weight / marginTop / marginBottom / marginStart / marginEnd
function M.applyLinearParams(view, opts)
  if view == nil then return view end
  local o = opts or {}
  local ok = pcall(function()
    local params = LinearLayoutParams(sizeToPx(o.width or "match"), sizeToPx(o.height or "wrap"))
    if o.weight ~= nil then params.weight = o.weight end
    local top = sizeToPx(o.marginTop or 0)
    local bottom = sizeToPx(o.marginBottom or 0)
    local start = sizeToPx(o.marginStart or 0)
    local endMargin = sizeToPx(o.marginEnd or 0)
    params.setMargins(start, top, endMargin, bottom)
    view.setLayoutParams(params)
  end)
  return ok and view or view
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
  if o.marginStart then spec.layout_marginStart = o.marginStart .. "dp" end
  if o.marginEnd then spec.layout_marginEnd = o.marginEnd .. "dp" end
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.marginBottom then spec.layout_marginBottom = o.marginBottom .. "dp" end
  return load(spec)
end

-- ===== 间距 =====
function M.spacer(heightDp)
  return load({
    Space,
    layout_width = "match",
    layout_height = tostring(heightDp) .. "dp",
  })
end

function M.divider(marginTop, marginBottom)
  local colors = theme.colors()
  return load({
    MaterialDivider,
    layout_width = "match",
    layout_height = "1dp",
    layout_marginTop = (marginTop or 0) .. "dp",
    layout_marginBottom = (marginBottom or 0) .. "dp",
    dividerColor = colors.outlineVariant,
  })
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
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.marginBottom then spec.layout_marginBottom = o.marginBottom .. "dp" end
  if o.marginStart then spec.layout_marginStart = o.marginStart .. "dp" end
  if o.marginEnd then spec.layout_marginEnd = o.marginEnd .. "dp" end
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
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.background then spec.BackgroundColor = o.background end
  if o.id then spec.id = o.id end
  for _, child in ipairs(children or {}) do
    if child ~= nil then spec[#spec + 1] = child end
  end
  local view = load(spec)
  if o.weight ~= nil then
    M.applyLinearParams(view, {
      width = o.width, height = o.height, weight = o.weight, marginTop = o.marginTop,
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
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.marginBottom then spec.layout_marginBottom = o.marginBottom .. "dp" end
  if o.marginHorizontal then
    spec.layout_marginStart = o.marginHorizontal .. "dp"
    spec.layout_marginEnd = o.marginHorizontal .. "dp"
  end
  if o.weight then spec.layout_weight = o.weight end
  if o.id then spec.id = o.id end

  local inner = M.column(children or {}, {
    width = "match",
    height = "wrap",
    padding = o.padding or 16,
  })
  spec[#spec + 1] = inner
  local card = load(spec)
  -- 根卡片自身的 LayoutParams 不支持 weight，必须在加入父容器前显式替换
  if o.weight ~= nil then
    M.applyLinearParams(card, {
      width = o.width or "match",
      height = o.height or "wrap",
      weight = o.weight,
      marginTop = o.marginTop,
      marginBottom = o.marginBottom,
      marginStart = o.marginHorizontal or o.marginStart,
      marginEnd = o.marginHorizontal or o.marginEnd,
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
  local spec = {
    MaterialButton,
    layout_width = o.width or "wrap",
    layout_height = o.height or "48dp",
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
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.marginStart then spec.layout_marginStart = o.marginStart .. "dp" end
  if o.marginEnd then spec.layout_marginEnd = o.marginEnd .. "dp" end
  local button = load(spec)
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
function M.listItem(opts)
  local o = opts or {}
  local colors = theme.colors()
  local container = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = (o.paddingHorizontal or 16) .. "dp",
    paddingEnd = (o.paddingHorizontal or 16) .. "dp",
    paddingTop = (o.paddingVertical or 14) .. "dp",
    paddingBottom = (o.paddingVertical or 14) .. "dp",
  })

  if o.icon then
    local holder = load({
      FrameLayout,
      layout_width = "40dp",
      layout_height = "40dp",
      layout_marginEnd = "16dp",
    })
    local iconView = M.icon(o.icon, o.iconSize or 22, o.iconColor or colors.primary)
    holder.addView(iconView, M.centeredParams())
    container.addView(holder)
  end

  local textHolder = load({
    LinearLayout,
    orientation = "vertical",
    layout_width = "0dp",
    layout_height = "wrap",
    layout_weight = 1,
  })
  textHolder.addView(M.text(o.title or "", {
    size = o.titleSize or M.TYPOGRAPHY.body,
    color = o.titleColor or colors.onSurface,
  }))
  if o.subtitle and o.subtitle ~= "" then
    local subtitle = M.text(o.subtitle, {
      size = M.TYPOGRAPHY.label,
      color = o.subtitleColor or colors.onSurfaceVariant,
      maxLines = o.subtitleMaxLines or 3,
    })
    local params = subtitle.getLayoutParams()
    if params ~= nil then params.topMargin = theme.dp(3) end
    textHolder.addView(subtitle)
  end
  container.addView(textHolder)

  if o.trailingText then
    container.addView(M.text(o.trailingText, {
      size = M.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }))
  end
  if o.trailingView ~= nil then
    container.addView(o.trailingView)
  elseif o.trailingIcon then
    container.addView(M.icon(o.trailingIcon, 18, colors.onSurfaceVariant))
  elseif o.showChevron then
    container.addView(M.icon("chevron_right", 18, colors.outline))
  end

  if o.onClick ~= nil then
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
  if o.marginTop then spec.layout_marginTop = o.marginTop .. "dp" end
  if o.marginStart then spec.layout_marginStart = o.marginStart .. "dp" end
  if o.marginEnd then spec.layout_marginEnd = o.marginEnd .. "dp" end
  local card = load(spec)

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
    paddingBottom = "12dp",
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
    paddingStart = "20dp",
    paddingEnd = "16dp",
    paddingTop = "16dp",
    paddingBottom = "8dp",
  })
  local textHolder = load({
    LinearLayout,
    orientation = "vertical",
    layout_width = "0dp",
    layout_height = "wrap",
    layout_weight = 1,
  })
  textHolder.addView(M.text(title, {
    size = M.TYPOGRAPHY.display,
    color = colors.onSurface,
    bold = true,
  }))
  if subtitle and subtitle ~= "" then
    local subtitleView = M.text(subtitle, {
      size = M.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    })
    local params = subtitleView.getLayoutParams()
    if params ~= nil then params.topMargin = theme.dp(4) end
    textHolder.addView(subtitleView)
  end
  header.addView(textHolder)
  for _, action in ipairs(actions or {}) do header.addView(action) end
  return header
end

-- 分组标题
function M.sectionTitle(title, actionLabel, onAction)
  local colors = theme.colors()
  local row = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "match",
    layout_height = "wrap",
    gravity = "start|center_vertical",
    paddingStart = "20dp",
    paddingEnd = "20dp",
    paddingTop = "14dp",
    paddingBottom = "6dp",
  })
  local holder = load({
    LinearLayout,
    orientation = "horizontal",
    layout_width = "0dp",
    layout_height = "wrap",
    layout_weight = 1,
  })
  holder.addView(M.text(title, {
    size = M.TYPOGRAPHY.label,
    color = colors.primary,
    bold = true,
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

-- 分组容器（圆角卡片，内部列表项 + 分割线）
function M.group(items)
  local colors = theme.colors()
  local children = {}
  for index, item in ipairs(items) do
    if index > 1 then
      children[#children + 1] = load({
        MaterialDivider,
        layout_width = "match",
        layout_height = "1dp",
        layout_marginStart = "16dp",
        dividerColor = colors.outlineVariant,
      })
    end
    children[#children + 1] = item
  end
  return M.card(children, { padding = 0, marginHorizontal = 16, marginTop = 4, marginBottom = 4 })
end

return M
