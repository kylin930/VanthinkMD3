-- 边距修复方案验证（开发期工具）
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_margin3.txt"

local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(out, "\n")) end) end
flush()

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
pcall(function() theme.bootstrap() end)
local dp = theme.dp

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
local LinearLayoutParams = luajava.bindClass("android.widget.LinearLayout$LayoutParams")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MeasureSpec = luajava.bindClass("android.view.View$MeasureSpec")

local function measureIn(host, widthPx)
  local wSpec = MeasureSpec.makeMeasureSpec(widthPx, MeasureSpec.EXACTLY)
  local hSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
  pcall(function()
    host.measure(wSpec, hSpec)
    host.layout(0, 0, host.getMeasuredWidth(), host.getMeasuredHeight())
  end)
end

local screenWidth = activity.getResources().getDisplayMetrics().widthPixels

-- 1) 原始根视图的 width/height 字段是否可用
local raw = loadlayout({
  MaterialTextView,
  layout_width = "match",
  layout_height = "wrap",
  text = "x",
  textSize = "14sp",
})
local rawLp = raw.getLayoutParams()
log("[1] raw root LP width/height")
log("  class=" .. tostring(rawLp.getClass().getName())
  .. " width=" .. tostring(rawLp.width) .. " height=" .. tostring(rawLp.height))
log("  MATCH_PARENT=" .. tostring(-1) .. " WRAP_CONTENT=" .. tostring(-2))

-- 2) 手动构造 LinearLayout.LayoutParams 应用边距
local col = LinearLayout(activity)
col.setOrientation(LinearLayout.VERTICAL)
local title = kit.text("标题文字", { size = 14 })
local params = LinearLayoutParams(rawLp.width, rawLp.height)
params.setMargins(dp(16), dp(24), dp(16), dp(8))
title.setLayoutParams(params)
col.addView(title)
measureIn(col, screenWidth)
log("")
log("[2] manual LinearLayoutParams margins")
log("  measured=" .. tostring(title.getMeasuredWidth()) .. "x" .. tostring(title.getMeasuredHeight())
  .. " left=" .. tostring(title.getLeft()) .. " top=" .. tostring(title.getTop())
  .. " right=" .. tostring(title.getRight()))
log("  expect left=" .. dp(16) .. " top=" .. dp(24)
  .. " width=" .. (screenWidth - dp(32)))

-- 3) LinearLayout.LayoutParams 放进 FrameLayout 是否会崩
log("")
log("[3] LinearLayout.LayoutParams inside FrameLayout")
local okFrame, errFrame = pcall(function()
  local frame = FrameLayout(activity)
  local card = MaterialCardView(activity)
  card.setLayoutParams(LinearLayoutParams(-1, -1))
  frame.addView(card)
  measureIn(frame, screenWidth)
  log("  未崩溃，measured=" .. tostring(card.getMeasuredWidth()))
end)
if not okFrame then log("  崩溃: " .. tostring(errFrame):gsub("\n", " "):sub(1, 200)) end

-- 4) weight 子视图保留权重 + 边距
local row = LinearLayout(activity)
row.setOrientation(LinearLayout.HORIZONTAL)
local half = kit.text("一半", { size = 14, width = "0dp", weight = 1 })
local halfLp = half.getLayoutParams()
local halfParams = LinearLayoutParams(halfLp.width, halfLp.height, halfLp.weight)
halfParams.setMargins(0, 0, dp(12), 0)
half.setLayoutParams(halfParams)
row.addView(half)
local other = kit.text("另一半", { size = 14, width = "0dp", weight = 1 })
local otherLp = other.getLayoutParams()
row.addView(other, LinearLayoutParams(otherLp.width, otherLp.height, otherLp.weight))
measureIn(row, screenWidth)
log("")
log("[4] weight + margin")
log("  half=" .. tostring(half.getMeasuredWidth()) .. " other=" .. tostring(other.getMeasuredWidth()))

flush()
print("probe_margin3 done -> " .. OUT)
