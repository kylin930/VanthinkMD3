-- 卡片外边距实测（开发期工具）
-- 目的：确认 kit.card 的 marginHorizontal / marginTop / marginBottom 在
--      加入父容器后是否真的生效（loadlayout 根视图的 LayoutParams 类型问题）。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_margin.txt"

local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(out, "\n")) end) end
flush()

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
pcall(function() theme.bootstrap() end)
local dp = theme.dp

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
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
log("screen width px = " .. screenWidth .. " (" .. kit.windowWidthDp() .. "dp)")

local column = LinearLayout(activity)
column.setOrientation(LinearLayout.VERTICAL)
local card = kit.card({ kit.text("测试卡片", { size = 14 }) }, {
  marginHorizontal = 16, marginTop = 12, marginBottom = 8, padding = 16,
})
column.addView(card)
measureIn(column, screenWidth)

local lp = card.getLayoutParams()
log("")
log("[card in vertical LinearLayout]")
log("  LP class = " .. tostring(lp and lp.getClass().getName()))
log("  left margin = " .. tostring(lp and lp.leftMargin) .. "px")
log("  top margin = " .. tostring(lp and lp.topMargin) .. "px")
log("  bottom margin = " .. tostring(lp and lp.bottomMargin) .. "px")
log("  right margin = " .. tostring(lp and lp.rightMargin) .. "px")
log("  measured = " .. tostring(card.getMeasuredWidth()) .. "x" .. tostring(card.getMeasuredHeight()))
pcall(function()
  log("  left/top/right/bottom = " .. tostring(card.getLeft()) .. "," .. tostring(card.getTop())
    .. "," .. tostring(card.getRight()) .. "," .. tostring(card.getBottom()))
end)
log("  expect left = " .. dp(16) .. "px, width = " .. (screenWidth - dp(32)) .. "px")

local row = LinearLayout(activity)
row.setOrientation(LinearLayout.HORIZONTAL)
local leftCard = kit.card({ kit.text("左", { size = 14 }) }, {
  width = "0dp", weight = 1, padding = 14,
})
local rightCard = kit.card({ kit.text("右", { size = 14 }) }, {
  width = "0dp", weight = 1, padding = 14,
})
row.addView(leftCard)
row.addView(rightCard)
measureIn(row, screenWidth)
log("")
log("[card with weight in horizontal LinearLayout]")
log("  left measured = " .. tostring(leftCard.getMeasuredWidth()) .. "px")
log("  right measured = " .. tostring(rightCard.getMeasuredWidth()) .. "px")
log("  LP = " .. tostring(leftCard.getLayoutParams().getClass().getName())
  .. " weight=" .. tostring(leftCard.getLayoutParams().weight))

flush()
print("probe_margin done -> " .. OUT)
