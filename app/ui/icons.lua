-- 图标：在 24x24 逻辑网格上用 android.graphics.Path 绘制，缓存为 BitmapDrawable。
-- 运行时不内置 Material Icons 资源（res.drawable 仅命中少量图标），
-- 因此这里用原生 Canvas 自绘，避免引入 WebView、字体或外部图片依赖。

local theme = require "app.ui.theme"

local M = {}

local Bitmap = luajava.bindClass("android.graphics.Bitmap")
local BitmapConfig = luajava.bindClass("android.graphics.Bitmap$Config")
local Canvas = luajava.bindClass("android.graphics.Canvas")
local Paint = luajava.bindClass("android.graphics.Paint")
local Path = luajava.bindClass("android.graphics.Path")
local RectF = luajava.bindClass("android.graphics.RectF")
local BitmapDrawable = luajava.bindClass("android.graphics.drawable.BitmapDrawable")

-- 图标定义：stroke = true 表示描边绘制，否则填充。
-- 坐标基于 24x24 网格。
local ICONS = {
  -- ===== 导航 =====
  assignment = {
    fill = true,
    ops = {
      { "m", 5, 3 }, { "l", 19, 3 }, { "q", 20, 3, 20, 4 }, { "l", 20, 21 }, { "q", 20, 22, 19, 22 },
      { "l", 5, 22 }, { "q", 4, 22, 4, 21 }, { "l", 4, 4 }, { "q", 4, 3, 5, 3 }, { "close" },
      { "m", 7, 7 }, { "l", 17, 7 }, { "l", 17, 9 }, { "l", 7, 9 }, { "close" },
      { "m", 7, 11 }, { "l", 17, 11 }, { "l", 17, 13 }, { "l", 7, 13 }, { "close" },
      { "m", 7, 15 }, { "l", 13, 15 }, { "l", 13, 17 }, { "l", 7, 17 }, { "close" },
    },
    evenOdd = true,
  },
  notifications = {
    fill = true,
    ops = {
      { "m", 12, 2 }, { "q", 8.5, 2, 8.5, 6 }, { "l", 8.5, 10 }, { "q", 8.5, 11.5, 7.5, 13 },
      { "q", 6.5, 14.5, 6.5, 15.5 }, { "l", 17.5, 15.5 }, { "q", 17.5, 14.5, 16.5, 13 },
      { "q", 15.5, 11.5, 15.5, 10 }, { "l", 15.5, 6 }, { "q", 15.5, 2, 12, 2 }, { "close" },
      { "m", 9.5, 17 }, { "q", 9.5, 21, 12, 21 }, { "q", 14.5, 21, 14.5, 17 }, { "close" },
    },
    evenOdd = true,
  },
  insights = {
    fill = true,
    ops = {
      { "m", 4, 13 }, { "l", 8, 13 }, { "l", 8, 20 }, { "l", 4, 20 }, { "close" },
      { "m", 10, 7 }, { "l", 14, 7 }, { "l", 14, 20 }, { "l", 10, 20 }, { "close" },
      { "m", 16, 10 }, { "l", 20, 10 }, { "l", 20, 20 }, { "l", 16, 20 }, { "close" },
    },
    evenOdd = true,
  },
  person = {
    fill = true,
    ops = {
      { "m", 12, 12 }, { "q", 15.3, 12, 15.3, 8.3 }, { "q", 15.3, 4.5, 12, 4.5 },
      { "q", 8.7, 4.5, 8.7, 8.3 }, { "q", 8.7, 12, 12, 12 }, { "close" },
      { "m", 4, 20 }, { "q", 4, 14.5, 12, 14.5 }, { "q", 20, 14.5, 20, 20 }, { "close" },
    },
    evenOdd = true,
  },

  -- ===== 导航未选中态（描边版，与上面的填充版共用 24×24 网格，视觉尺寸一致）=====
  assignment_outline = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 5, 3 }, { "l", 19, 3 }, { "q", 20, 3, 20, 4 }, { "l", 20, 21 },
      { "q", 20, 22, 19, 22 }, { "l", 5, 22 }, { "q", 4, 22, 4, 21 }, { "l", 4, 4 },
      { "q", 4, 3, 5, 3 },
      { "m", 7, 7 }, { "l", 17, 7 },
      { "m", 7, 11 }, { "l", 17, 11 },
      { "m", 7, 15 }, { "l", 13, 15 },
    },
  },
  notifications_outline = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 12, 2.6 }, { "q", 8.6, 2.6, 8.6, 6.4 }, { "l", 8.6, 10.2 },
      { "q", 8.6, 11.8, 7.4, 13.2 }, { "q", 6.4, 14.6, 6.4, 15.6 }, { "l", 17.6, 15.6 },
      { "q", 17.6, 14.6, 16.6, 13.2 }, { "q", 15.4, 11.8, 15.4, 10.2 }, { "l", 15.4, 6.4 },
      { "q", 15.4, 2.6, 12, 2.6 },
      { "m", 10, 18 }, { "q", 10, 21, 12, 21 }, { "q", 14, 21, 14, 18 },
    },
  },
  insights_outline = {
    stroke = true,
    width = 1.8,
    ops = {
      { "rect", 4, 13, 8, 20 },
      { "rect", 10, 7, 14, 20 },
      { "rect", 16, 10, 20, 20 },
    },
  },
  person_outline = {
    stroke = true,
    width = 1.8,
    ops = {
      { "circle", 12, 8.3, 3.5 },
      { "m", 5, 20 }, { "q", 5, 14.6, 12, 14.6 }, { "q", 19, 14.6, 19, 20 },
    },
  },

  -- ===== 操作 =====
  refresh = {
    stroke = true,
    width = 2.0,
    ops = {
      { "m", 20, 12 }, { "c", 20, 7.6, 16.4, 4, 12, 4 },
      { "c", 10.2, 4, 8.6, 4.7, 7.4, 5.8 },
      { "m", 4, 4 }, { "l", 4, 9 }, { "l", 9, 9 },
      { "m", 4, 12 }, { "c", 4, 16.4, 7.6, 20, 12, 20 },
      { "c", 13.8, 20, 15.4, 19.3, 16.6, 18.2 },
      { "m", 20, 20 }, { "l", 20, 15 }, { "l", 15, 15 },
    },
  },
  arrow_back = {
    stroke = true,
    width = 2.2,
    ops = { { "m", 19, 12 }, { "l", 5, 12 }, { "m", 11, 6 }, { "l", 5, 12 }, { "l", 11, 18 } },
  },
  share = {
    fill = true,
    ops = {
      { "m", 18, 15 }, { "q", 16.6, 15, 15.6, 15.6 }, { "l", 9.9, 12.3 },
      { "q", 10, 11.4, 9.9, 11.7 }, { "l", 15.6, 8.4 }, { "q", 16.6, 9, 18, 9 },
      { "q", 20.5, 9, 20.5, 6.5 }, { "q", 20.5, 4, 18, 4 }, { "q", 15.5, 4, 15.5, 6.5 },
      { "q", 15.5, 7.2, 15.7, 7.7 }, { "l", 10, 10.9 }, { "q", 9, 10.3, 7.6, 10.3 },
      { "q", 5.1, 10.3, 5.1, 12.8 }, { "q", 5.1, 15.3, 7.6, 15.3 }, { "q", 9, 15.3, 10, 14.6 },
      { "l", 15.7, 17.9 }, { "q", 15.5, 18.5, 15.5, 19.1 }, { "q", 15.5, 21.6, 18, 21.6 },
      { "q", 20.5, 21.6, 20.5, 19.1 }, { "q", 20.5, 16.6, 18, 16.6 }, { "close" },
    },
    evenOdd = true,
  },
  check = {
    stroke = true,
    width = 2.4,
    ops = { { "m", 5, 12.5 }, { "l", 10, 17.5 }, { "l", 19, 6.8 } },
  },
  close = {
    stroke = true,
    width = 2.2,
    ops = { { "m", 6, 6 }, { "l", 18, 18 }, { "m", 18, 6 }, { "l", 6, 18 } },
  },
  add = {
    stroke = true,
    width = 2.2,
    ops = { { "m", 12, 5 }, { "l", 12, 19 }, { "m", 5, 12 }, { "l", 19, 12 } },
  },
  chevron_right = {
    stroke = true,
    width = 2.2,
    ops = { { "m", 9, 5 }, { "l", 16, 12 }, { "l", 9, 19 } },
  },
  search = {
    stroke = true,
    width = 2.0,
    ops = {
      { "circle", 11, 11, 6.2 },
      { "m", 15.6, 15.6 }, { "l", 20, 20 },
    },
  },
  more_vert = {
    fill = true,
    ops = {
      { "circle", 12, 5, 1.7 },
      { "circle", 12, 12, 1.7 },
      { "circle", 12, 19, 1.7 },
    },
  },
  copy = {
    stroke = true,
    width = 1.8,
    ops = {
      { "rect", 9, 9, 20, 20 },
      { "m", 15, 9 }, { "l", 15, 4 }, { "l", 4, 4 }, { "l", 4, 15 }, { "l", 9, 15 },
    },
  },
  qr_code = {
    fill = true,
    ops = {
      { "rect", 3, 3, 9, 9 }, { "rect", 15, 3, 21, 9 }, { "rect", 3, 15, 9, 21 },
      { "hole", 5, 5, 7, 7 }, { "hole", 17, 5, 19, 7 }, { "hole", 5, 17, 7, 19 },
      { "rect", 15, 15, 17, 17 }, { "rect", 19, 15, 21, 17 }, { "rect", 15, 19, 17, 21 },
      { "rect", 19, 19, 21, 21 },
    },
    evenOdd = true,
  },

  -- ===== 状态与信息 =====
  schedule = {
    stroke = true,
    width = 1.9,
    ops = {
      { "circle", 12, 12, 8.2 },
      { "m", 12, 7.4 }, { "l", 12, 12.4 }, { "l", 15.6, 14.2 },
    },
  },
  star = {
    fill = true,
    ops = {
      { "m", 12, 3.2 }, { "l", 14.6, 9 }, { "l", 20.8, 9.8 }, { "l", 16.2, 14.2 },
      { "l", 17.4, 20.4 }, { "l", 12, 17.4 }, { "l", 6.6, 20.4 }, { "l", 7.8, 14.2 },
      { "l", 3.2, 9.8 }, { "l", 9.4, 9 }, { "close" },
    },
  },
  leaderboard = {
    fill = true,
    ops = {
      { "m", 9.5, 8 }, { "l", 14.5, 8 }, { "l", 14.5, 20 }, { "l", 9.5, 20 }, { "close" },
      { "m", 4, 12 }, { "l", 8, 12 }, { "l", 8, 20 }, { "l", 4, 20 }, { "close" },
      { "m", 16, 15 }, { "l", 20, 15 }, { "l", 20, 20 }, { "l", 16, 20 }, { "close" },
    },
    evenOdd = true,
  },
  task_alt = {
    stroke = true,
    width = 1.9,
    ops = {
      { "circle", 12, 12, 8.4 },
      { "m", 8.2, 12.2 }, { "l", 11, 15 }, { "l", 16, 9.4 },
    },
  },
  done_all = {
    stroke = true,
    width = 2.0,
    ops = {
      { "m", 2.5, 12.5 }, { "l", 6.5, 16.5 }, { "l", 14, 8.5 },
      { "m", 10.5, 15.5 }, { "l", 12.5, 17.5 }, { "l", 21, 8.5 },
    },
  },
  error = {
    fill = true,
    ops = {
      { "circle", 12, 12, 9 },
      { "hole_text", 0 },
    },
    evenOdd = false,
  },
  warning = {
    fill = true,
    ops = {
      { "m", 12, 3 }, { "l", 22, 20.5 }, { "l", 2, 20.5 }, { "close" },
    },
    evenOdd = false,
  },
  info = {
    stroke = true,
    width = 1.9,
    ops = {
      { "circle", 12, 12, 8.4 },
      { "m", 12, 10.8 }, { "l", 12, 17 },
      { "circle", 12, 7.8, 0.9 },
    },
  },
  cloud_off = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 7, 17.5 }, { "q", 3.4, 17.5, 3.4, 14.2 }, { "q", 3.4, 11.2, 6.4, 11 },
      { "q", 6.9, 7.6, 10.2, 6.9 },
      { "m", 14, 7.2 }, { "q", 18.5, 7.6, 18.5, 12.2 }, { "q", 21, 12.6, 21, 15 },
      { "q", 21, 17.4, 18.6, 17.5 },
      { "m", 3.5, 3.5 }, { "l", 20.5, 20.5 },
    },
  },
  inbox = {
    stroke = true,
    width = 1.8,
    ops = {
      { "rect", 3.2, 4.5, 20.8, 19.5 },
      { "m", 3.2, 13 }, { "l", 8, 13 }, { "l", 9.4, 15 }, { "l", 14.6, 15 }, { "l", 16, 13 },
      { "l", 20.8, 13 },
    },
  },
  lock = {
    fill = true,
    ops = {
      { "m", 6, 10 }, { "l", 18, 10 }, { "l", 18, 21 }, { "l", 6, 21 }, { "close" },
      { "stroke", true },
      { "m", 8.5, 10 }, { "l", 8.5, 7.4 }, { "q", 8.5, 3.6, 12, 3.6 },
      { "q", 15.5, 3.6, 15.5, 7.4 }, { "l", 15.5, 10 },
    },
    evenOdd = false,
  },
  visibility = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 2.2, 12 }, { "q", 6, 5.8, 12, 5.8 }, { "q", 18, 5.8, 21.8, 12 },
      { "q", 18, 18.2, 12, 18.2 }, { "q", 6, 18.2, 2.2, 12 }, { "close" },
      { "circle", 12, 12, 2.9 },
    },
  },
  visibility_off = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 2.2, 12 }, { "q", 6, 5.8, 12, 5.8 }, { "q", 18, 5.8, 21.8, 12 },
      { "q", 16.6, 16.9, 11.4, 17.9 },
      { "m", 3.5, 3.5 }, { "l", 20.5, 20.5 },
    },
  },
  palette = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 12, 3.4 }, { "q", 20.6, 3.4, 20.6, 12 }, { "q", 20.6, 16.4, 16.4, 16.4 },
      { "l", 14.2, 16.4 }, { "q", 12.4, 16.4, 12.4, 18.2 }, { "q", 12.4, 20.6, 9.6, 20.6 },
      { "q", 3.4, 20.6, 3.4, 12 }, { "q", 3.4, 3.4, 12, 3.4 }, { "close" },
      { "circle", 8, 10, 1.1 },
      { "circle", 12, 7.4, 1.1 },
      { "circle", 16, 10, 1.1 },
    },
  },
  settings = {
    stroke = true,
    width = 1.8,
    ops = {
      { "circle", 12, 12, 3.2 },
      { "circle", 12, 12, 7.6 },
      { "m", 12, 2.2 }, { "l", 12, 4.6 },
      { "m", 12, 19.4 }, { "l", 12, 21.8 },
      { "m", 2.2, 12 }, { "l", 4.6, 12 },
      { "m", 19.4, 12 }, { "l", 21.8, 12 },
    },
  },
  logout = {
    stroke = true,
    width = 1.9,
    ops = {
      { "m", 12, 3.5 }, { "l", 5, 3.5 }, { "l", 5, 20.5 }, { "l", 12, 20.5 },
      { "m", 10, 12 }, { "l", 20.5, 12 },
      { "m", 16.5, 8 }, { "l", 20.5, 12 }, { "l", 16.5, 16 },
    },
  },
  dark_mode = {
    fill = true,
    ops = {
      { "m", 13.2, 3 }, { "q", 8.4, 5.6, 8.4, 12 }, { "q", 8.4, 18.4, 13.2, 21 },
      { "q", 4.4, 21.4, 4.4, 12 }, { "q", 4.4, 5.4, 13.2, 3 }, { "close" },
    },
  },
  light_mode = {
    stroke = true,
    width = 1.8,
    ops = {
      { "circle", 12, 12, 4.6 },
      { "m", 12, 2 }, { "l", 12, 4.2 },
      { "m", 12, 19.8 }, { "l", 12, 22 },
      { "m", 2, 12 }, { "l", 4.2, 12 },
      { "m", 19.8, 12 }, { "l", 22, 12 },
      { "m", 4.9, 4.9 }, { "l", 6.5, 6.5 },
      { "m", 17.5, 17.5 }, { "l", 19.1, 19.1 },
      { "m", 19.1, 4.9 }, { "l", 17.5, 6.5 },
      { "m", 6.5, 17.5 }, { "l", 4.9, 19.1 },
    },
  },
  color_lens = {
    fill = true,
    ops = {
      { "circle", 12, 12, 8.6 },
      { "hole_circle", 7.6, 9.4, 1.5 },
      { "hole_circle", 12, 7, 1.5 },
      { "hole_circle", 16.4, 9.4, 1.5 },
    },
    evenOdd = true,
  },
  update = {
    stroke = true,
    width = 1.9,
    ops = {
      { "m", 12, 3.6 }, { "c", 16.6, 3.6, 20.4, 7.4, 20.4, 12 },
      { "m", 12, 20.4 }, { "c", 7.4, 20.4, 3.6, 16.6, 3.6, 12 },
      { "m", 12, 7.4 }, { "l", 12, 12.6 }, { "l", 15.8, 14.6 },
    },
  },
  history = {
    stroke = true,
    width = 1.9,
    ops = {
      { "circle", 12, 12, 8.2 },
      { "m", 12, 7.6 }, { "l", 12, 12.4 }, { "l", 15.4, 14 },
    },
  },
  school = {
    fill = true,
    ops = {
      { "m", 12, 3.5 }, { "l", 22, 7.6 }, { "l", 12, 11.7 }, { "l", 2, 7.6 }, { "close" },
      { "m", 5.4, 10.2 }, { "l", 5.4, 15.4 }, { "q", 5.4, 18.4, 12, 18.4 },
      { "q", 18.6, 18.4, 18.6, 15.4 }, { "l", 18.6, 10.2 }, { "l", 16.8, 11 }, { "l", 16.8, 15 },
      { "q", 16.8, 16.8, 12, 16.8 }, { "q", 7.2, 16.8, 7.2, 15 }, { "l", 7.2, 11 }, { "close" },
    },
    evenOdd = true,
  },
  mic = {
    fill = true,
    ops = {
      { "m", 12, 2.6 }, { "q", 9.4, 2.6, 9.4, 6.4 }, { "l", 9.4, 11.4 },
      { "q", 9.4, 15.2, 12, 15.2 }, { "q", 14.6, 15.2, 14.6, 11.4 }, { "l", 14.6, 6.4 },
      { "q", 14.6, 2.6, 12, 2.6 }, { "close" },
      { "stroke", true },
      { "m", 6, 11.6 }, { "q", 6, 18.2, 12, 18.2 }, { "q", 18, 18.2, 18, 11.6 },
      { "m", 12, 18.2 }, { "l", 12, 21.4 },
    },
    evenOdd = false,
  },
  menu_book = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 12, 6.4 }, { "q", 9.4, 4.4, 3.4, 4.6 }, { "l", 3.4, 18.6 },
      { "q", 9.4, 18.4, 12, 20.4 },
      { "q", 14.6, 18.4, 20.6, 18.6 }, { "l", 20.6, 4.6 },
      { "q", 14.6, 4.4, 12, 6.4 }, { "l", 12, 20.4 },
    },
  },
  trending_up = {
    stroke = true,
    width = 2.0,
    ops = {
      { "m", 3.4, 17.4 }, { "l", 9.4, 11.4 }, { "l", 13.2, 15.2 }, { "l", 20.6, 7.8 },
      { "m", 15.4, 7.8 }, { "l", 20.6, 7.8 }, { "l", 20.6, 13 },
    },
  },
  open_in_new = {
    stroke = true,
    width = 1.8,
    ops = {
      { "m", 13, 4.4 }, { "l", 19.6, 4.4 }, { "l", 19.6, 11 },
      { "m", 19.6, 4.4 }, { "l", 11, 13 },
      { "m", 17, 14 }, { "l", 17, 19.6 }, { "l", 4.4, 19.6 }, { "l", 4.4, 7 }, { "l", 10, 7 },
    },
  },
  filter = {
    fill = true,
    ops = {
      { "m", 3.4, 5.4 }, { "l", 20.6, 5.4 }, { "l", 14, 13.2 }, { "l", 14, 20.6 },
      { "l", 10, 18.4 }, { "l", 10, 13.2 }, { "close" },
    },
  },
}

local DEFAULT_COLOR = 0xFFFFFFFF

local cache = {}

local function buildBitmap(def, sizePx, color)
  local bitmap = Bitmap.createBitmap(sizePx, sizePx, BitmapConfig.ARGB_8888)
  local canvas = Canvas(bitmap)
  local scale = sizePx / 24
  local tint = theme.normalize(color or 0xFFFFFFFF)

  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setDither(true)

  local path = Path()
  local fillPaint = Paint()
  fillPaint.setAntiAlias(true)
  fillPaint.setColor(tint)
  fillPaint.setStyle(Paint.Style.FILL)

  local strokePaint = Paint()
  strokePaint.setAntiAlias(true)
  strokePaint.setColor(tint)
  strokePaint.setStyle(Paint.Style.STROKE)
  strokePaint.setStrokeCap(Paint.Cap.ROUND)
  strokePaint.setStrokeJoin(Paint.Join.ROUND)
  local strokeWidth = (def.width or 2.0) * scale
  strokePaint.setStrokeWidth(strokeWidth)

  local function scaled(value) return value * scale end

  fillPaint.setPathEffect(nil)
  -- 描边模式下把坐标向内收半个线宽，避免被裁切
  local inset = def.stroke and strokeWidth / 2 or 0

  local closed = false
  for _, op in ipairs(def.ops) do
    local kind = op[1]
    if kind == "m" then
      path.moveTo(scaled(op[2]) + inset, scaled(op[3]) + inset)
    elseif kind == "l" then
      path.lineTo(scaled(op[2]) + inset, scaled(op[3]) + inset)
    elseif kind == "q" then
      path.quadTo(scaled(op[2]) + inset, scaled(op[3]) + inset,
        scaled(op[4]) + inset, scaled(op[5]) + inset)
    elseif kind == "c" then
      path.cubicTo(scaled(op[2]) + inset, scaled(op[3]) + inset,
        scaled(op[4]) + inset, scaled(op[5]) + inset,
        scaled(op[6]) + inset, scaled(op[7]) + inset)
    elseif kind == "close" then
      path.close()
      closed = true
    elseif kind == "circle" then
      local cx, cy, r = scaled(op[2]), scaled(op[3]), scaled(op[4])
      if def.stroke then
        canvas.drawCircle(cx, cy, r - inset, strokePaint)
      else
        canvas.drawCircle(cx, cy, r, fillPaint)
      end
    elseif kind == "rect" then
      local left, top, right, bottom = scaled(op[2]), scaled(op[3]), scaled(op[4]), scaled(op[5])
      if def.stroke then
        canvas.drawRect(left + inset, top + inset, right - inset, bottom - inset, strokePaint)
      else
        local rect = RectF(left, top, right, bottom)
        canvas.drawRect(rect, fillPaint)
      end
    elseif kind == "hole" or kind == "hole_circle" then
      -- 由 evenOdd 填充规则处理，无需额外动作
    elseif kind == "stroke" then
      -- 后续操作改用描边（混合图标）
      canvas.drawPath(path, closed and fillPaint or strokePaint)
      path.reset()
    else
      -- 未知操作忽略
    end
  end

  if def.stroke then
    canvas.drawPath(path, strokePaint)
  else
    path.setFillType(def.evenOdd and Path.FillType.EVEN_ODD or Path.FillType.WINDING)
    canvas.drawPath(path, fillPaint)
  end

  return bitmap
end

-- 获取图标 Drawable
function M.get(name, sizeDp, color)
  local def = ICONS[name]
  if def == nil then
    -- 未定义图标回退为圆形，避免界面出现空白
    def = { fill = true, ops = { { "circle", 12, 12, 8 } } }
  end
  local size = math.max(8, math.floor(sizeDp or 24))
  local tint = theme.normalize(color or theme.colors().onSurfaceVariant)
  local key = name .. "|" .. size .. "|" .. tostring(tint)
  if cache[key] ~= nil then return cache[key] end
  local ok, drawable = pcall(function()
    local px = theme.dp(size)
    local bitmap = buildBitmap(def, px, tint)
    local d = BitmapDrawable(activity.getResources(), bitmap)
    d.setBounds(0, 0, px, px)
    return d
  end)
  if not ok then return nil end
  cache[key] = drawable
  return drawable
end

function M.has(name)
  return ICONS[name] ~= nil
end

return M
