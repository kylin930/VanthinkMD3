-- 图表：使用原生 Canvas 自绘（Bitmap + ImageView），不引入 WebView 或第三方图表库。
-- 提供柱状图与折线图，支持坐标标签抽样与数值缩写，颜色取自主题。

local theme = require "app.ui.theme"
local formatter = require "app.utils.formatter"

local M = {}

local Bitmap = luajava.bindClass("android.graphics.Bitmap")
local BitmapConfig = luajava.bindClass("android.graphics.Bitmap$Config")
local Canvas = luajava.bindClass("android.graphics.Canvas")
local Paint = luajava.bindClass("android.graphics.Paint")
local Path = luajava.bindClass("android.graphics.Path")
local RectF = luajava.bindClass("android.graphics.RectF")
local BitmapDrawable = luajava.bindClass("android.graphics.drawable.BitmapDrawable")
local ImageView = luajava.bindClass("android.widget.ImageView")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local Typeface = luajava.bindClass("android.graphics.Typeface")
local AsyncDrawable = nil

local function newPaint()
  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setDither(true)
  return paint
end

-- 统一把颜色归一化为 Java int（Lua 的 0xFFxxxxxx 是无符号正数）
local function color(value)
  return theme.normalize(value)
end

-- 数值缩写：1.2k / 3.4w
local function shortNumber(value)
  local number = tonumber(value) or 0
  if number >= 10000 then
    return string.format("%.1fw", number / 10000)
  end
  if number >= 1000 then
    return string.format("%.1fk", number / 1000)
  end
  if number == math.floor(number) then
    return tostring(math.floor(number))
  end
  return string.format("%.1f", number)
end

-- 标签抽样：最多 maxCount 个
local function sampleIndices(count, maxCount)
  if count <= maxCount then
    local all = {}
    for i = 1, count do all[i] = i end
    return all
  end
  local step = (count - 1) / (maxCount - 1)
  local indices = {}
  for i = 0, maxCount - 1 do
    indices[#indices + 1] = math.floor(i * step + 0.5) + 1
  end
  return indices
end

local function createImageView(widthPx, heightPx)
  local view = loadlayout({
    ImageView,
    layout_width = "match",
    layout_height = math.floor(heightPx / theme.dp(1)) .. "dp",
    scaleType = "fitXY",
  })
  return view
end

-- 图表位图宽度：屏幕宽度减去卡片两侧的外边距与内边距（默认页面边距 16dp + 内边距 12dp）。
-- 位图由 ImageView 以 fitXY 铺满可用宽度，这里只要保证与实际可用宽度接近，
-- 避免图表被横向控件挤压或出现缩放失真。
local function measureWidth(insetDp)
  local metrics = activity.getResources().getDisplayMetrics()
  local inset = theme.dp((insetDp or 28) * 2)
  return math.max(theme.dp(200), metrics.widthPixels - inset)
end

-- 绘制坐标轴与网格，返回绘图区
local function drawGrid(canvas, widthPx, heightPx, maxValue, padding, colors)
  local gridPaint = newPaint()
  gridPaint.setColor(color(colors.outlineVariant))
  gridPaint.setStrokeWidth(math.max(1, theme.dp(1) * 0.5))

  local textPaint = newPaint()
  textPaint.setColor(color(colors.onSurfaceVariant))
  textPaint.setTextSize(theme.sp(10))
  textPaint.setTextAlign(Paint.Align.RIGHT)

  local plotLeft = padding.left
  local plotTop = padding.top
  local plotRight = widthPx - padding.right
  local plotBottom = heightPx - padding.bottom

  local lines = 4
  for i = 0, lines do
    local ratio = i / lines
    local y = plotBottom - ratio * (plotBottom - plotTop)
    canvas.drawLine(plotLeft, y, plotRight, y, gridPaint)
    local value = maxValue * ratio
    canvas.drawText(shortNumber(value), plotLeft - theme.dp(6), y + theme.dp(3), textPaint)
  end

  return plotLeft, plotTop, plotRight, plotBottom
end

local function axisLabelPaint(colors)
  local paint = newPaint()
  paint.setColor(color(colors.onSurfaceVariant))
  paint.setTextSize(theme.sp(10))
  paint.setTextAlign(Paint.Align.CENTER)
  return paint
end

-- 柱状图
-- opts: points = { {label = "01/02", value = 12}, ... }, heightDp
function M.barChart(opts)
  local o = opts or {}
  local points = o.points or {}
  local heightDp = o.heightDp or 180
  local colors = theme.colors()

  local widthPx = measureWidth(o.insetDp)
  local heightPx = theme.dp(heightDp)
  local bitmap = Bitmap.createBitmap(widthPx, heightPx, BitmapConfig.ARGB_8888)
  local canvas = Canvas(bitmap)

  local padding = {
    left = theme.dp(34),
    top = theme.dp(12),
    right = theme.dp(8),
    bottom = theme.dp(24),
  }

  if #points == 0 then
    local paint = newPaint()
    paint.setColor(color(colors.onSurfaceVariant))
    paint.setTextSize(theme.sp(12))
    paint.setTextAlign(Paint.Align.CENTER)
    canvas.drawText("暂无数据", widthPx / 2, heightPx / 2, paint)
    local view = createImageView(widthPx, heightPx)
    view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
    return view
  end

  local maxValue = 0
  for _, point in ipairs(points) do
    if point.value > maxValue then maxValue = point.value end
  end
  if maxValue <= 0 then maxValue = 1 end

  local plotLeft, plotTop, plotRight, plotBottom = drawGrid(canvas, widthPx, heightPx, maxValue, padding, colors)

  local barPaint = newPaint()
  barPaint.setColor(color(colors.primary))

  local count = #points
  local slot = (plotRight - plotLeft) / count
  local barWidth = math.max(theme.dp(3), math.min(theme.dp(22), slot * 0.55))
  local radius = math.min(theme.dp(4), barWidth / 2)

  local labelPaint = axisLabelPaint(colors)
  local labelIndices = sampleIndices(count, 7)

  for index, point in ipairs(points) do
    local centerX = plotLeft + slot * (index - 0.5)
    local value = math.max(0, point.value)
    local barHeight = (value / maxValue) * (plotBottom - plotTop)
    if barHeight < theme.dp(1) then barHeight = theme.dp(1) end
    local left = centerX - barWidth / 2
    local right = centerX + barWidth / 2
    local top = plotBottom - barHeight
    local rect = RectF(left, top, right, plotBottom)
    canvas.drawRoundRect(rect, radius, radius, barPaint)
  end

  for _, index in ipairs(labelIndices) do
    local centerX = plotLeft + slot * (index - 0.5)
    canvas.drawText(tostring(points[index].label or ""), centerX, plotBottom + theme.dp(15), labelPaint)
  end

  local view = createImageView(widthPx, heightPx)
  view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
  return view
end

-- 折线图（含渐变面积填充）
function M.lineChart(opts)
  local o = opts or {}
  local points = o.points or {}
  local heightDp = o.heightDp or 180
  local colors = theme.colors()

  local widthPx = measureWidth(o.insetDp)
  local heightPx = theme.dp(heightDp)
  local bitmap = Bitmap.createBitmap(widthPx, heightPx, BitmapConfig.ARGB_8888)
  local canvas = Canvas(bitmap)

  local padding = {
    left = theme.dp(34),
    top = theme.dp(12),
    right = theme.dp(8),
    bottom = theme.dp(24),
  }

  if #points == 0 then
    local paint = newPaint()
    paint.setColor(color(colors.onSurfaceVariant))
    paint.setTextSize(theme.sp(12))
    paint.setTextAlign(Paint.Align.CENTER)
    canvas.drawText("暂无数据", widthPx / 2, heightPx / 2, paint)
    local view = createImageView(widthPx, heightPx)
    view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
    return view
  end

  local maxValue = 0
  for _, point in ipairs(points) do
    if point.value > maxValue then maxValue = point.value end
  end
  if maxValue <= 0 then maxValue = 1 end
  maxValue = maxValue * 1.1

  local plotLeft, plotTop, plotRight, plotBottom = drawGrid(canvas, widthPx, heightPx, maxValue, padding, colors)

  local count = #points
  local slot
  if count == 1 then
    slot = plotRight - plotLeft
  else
    slot = (plotRight - plotLeft) / (count - 1)
  end

  local linePath = Path()
  local areaPath = Path()
  local xs, ys = {}, {}
  for index, point in ipairs(points) do
    local x
    if count == 1 then
      x = (plotLeft + plotRight) / 2
    else
      x = plotLeft + slot * (index - 1)
    end
    local ratio = math.max(0, point.value) / maxValue
    local y = plotBottom - ratio * (plotBottom - plotTop)
    xs[index] = x
    ys[index] = y
    if index == 1 then
      linePath.moveTo(x, y)
      areaPath.moveTo(x, plotBottom)
      areaPath.lineTo(x, y)
    else
      linePath.lineTo(x, y)
      areaPath.lineTo(x, y)
    end
  end
  areaPath.lineTo(xs[count], plotBottom)
  areaPath.close()

  local areaPaint = newPaint()
  areaPaint.setColor(color(colors.primary))
  areaPaint.setAlpha(36)
  areaPaint.setStyle(Paint.Style.FILL)
  canvas.drawPath(areaPath, areaPaint)

  local linePaint = newPaint()
  linePaint.setColor(color(colors.primary))
  linePaint.setStyle(Paint.Style.STROKE)
  linePaint.setStrokeWidth(math.max(2, theme.dp(2)))
  linePaint.setStrokeCap(Paint.Cap.ROUND)
  linePaint.setStrokeJoin(Paint.Join.ROUND)
  canvas.drawPath(linePath, linePaint)

  if count <= 31 then
    local dotPaint = newPaint()
    dotPaint.setColor(color(colors.primary))
    local dotRadius = theme.dp(2.6)
    for index = 1, count do
      canvas.drawCircle(xs[index], ys[index], dotRadius, dotPaint)
    end
  end

  local labelPaint = axisLabelPaint(colors)
  local labelIndices = sampleIndices(count, 7)
  for _, index in ipairs(labelIndices) do
    canvas.drawText(tostring(points[index].label or ""), xs[index], plotBottom + theme.dp(15), labelPaint)
  end

  local view = createImageView(widthPx, heightPx)
  view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
  return view
end

-- 迷你进度环（作业卡片完成率）
function M.progressRing(percent, sizeDp)
  local colors = theme.colors()
  local size = theme.dp(sizeDp or 44)
  local bitmap = Bitmap.createBitmap(size, size, BitmapConfig.ARGB_8888)
  local canvas = Canvas(bitmap)
  local stroke = size * 0.14
  local inset = stroke / 2 + 1

  local trackPaint = newPaint()
  trackPaint.setColor(color(colors.surfaceContainerHighest))
  trackPaint.setStyle(Paint.Style.STROKE)
  trackPaint.setStrokeWidth(stroke)
  canvas.drawCircle(size / 2, size / 2, size / 2 - inset, trackPaint)

  local value = math.max(0, math.min(100, tonumber(percent) or 0))
  local arcPaint = newPaint()
  arcPaint.setColor(color(value >= 100 and colors.tertiary or colors.primary))
  arcPaint.setStyle(Paint.Style.STROKE)
  arcPaint.setStrokeWidth(stroke)
  arcPaint.setStrokeCap(Paint.Cap.ROUND)
  local rect = RectF(inset, inset, size - inset, size - inset)
  if value > 0 then
    canvas.drawArc(rect, -90, 360 * value / 100, false, arcPaint)
  end

  local view = loadlayout({
    ImageView,
    layout_width = tostring(sizeDp or 44) .. "dp",
    layout_height = tostring(sizeDp or 44) .. "dp",
    scaleType = "fitXY",
  })
  view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
  return view
end

-- 二维码渲染（纯 Lua 编码器输出的布尔矩阵 → 位图）
function M.qrCode(matrix, sizeDp)
  if matrix == nil then return nil end
  local moduleCount = matrix.size
  local targetPx = theme.dp(sizeDp or 220)
  -- 每个模块取整数像素，保证边缘清晰
  local scale = math.max(1, math.floor(targetPx / (moduleCount + 8)))
  local quiet = 4
  local total = (moduleCount + quiet * 2) * scale
  local bitmap = Bitmap.createBitmap(total, total, BitmapConfig.ARGB_8888)
  local canvas = Canvas(bitmap)
  canvas.drawColor(theme.normalize(0xFFFFFFFF))

  local paint = newPaint()
  paint.setColor(theme.normalize(0xFF101418))
  for row = 1, moduleCount do
    for col = 1, moduleCount do
      if matrix.modules[row][col] then
        local left = (col - 1 + quiet) * scale
        local top = (row - 1 + quiet) * scale
        canvas.drawRect(RectF(left, top, left + scale, top + scale), paint)
      end
    end
  end

  local view = loadlayout({
    ImageView,
    layout_width = tostring(sizeDp or 220) .. "dp",
    layout_height = tostring(sizeDp or 220) .. "dp",
    scaleType = "fitXY",
  })
  view.setImageDrawable(BitmapDrawable(activity.getResources(), bitmap))
  return view
end

return M
