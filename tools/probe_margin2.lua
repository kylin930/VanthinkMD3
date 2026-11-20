-- loadlayout 根视图边距行为探测（开发期工具）
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_margin2.txt"

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
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
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

local raw = loadlayout({
  MaterialCardView,
  layout_width = "match",
  layout_height = "wrap",
  layout_marginStart = "16dp",
  layout_marginEnd = "16dp",
  layout_marginTop = "12dp",
})
log("[A] raw loadlayout root params (before addView)")
log("  LP = " .. tostring(raw.getLayoutParams() and raw.getLayoutParams().getClass().getName()))
pcall(function()
  local lp = raw.getLayoutParams()
  log("  left=" .. tostring(lp.leftMargin) .. " top=" .. tostring(lp.topMargin)
    .. " right=" .. tostring(lp.rightMargin) .. " bottom=" .. tostring(lp.bottomMargin))
end)

local col = LinearLayout(activity)
col.setOrientation(LinearLayout.VERTICAL)
local textWithMargin = loadlayout({
  MaterialTextView,
  layout_width = "match",
  layout_height = "wrap",
  text = "带 marginTop 的文本",
  textSize = "14sp",
  layout_marginTop = "24dp",
})
col.addView(textWithMargin)
measureIn(col, screenWidth)
log("")
log("[B] loadlayout root with layout_marginTop inside LinearLayout")
pcall(function()
  local lp = textWithMargin.getLayoutParams()
  log("  LP = " .. tostring(lp.getClass().getName()) .. " top=" .. tostring(lp.topMargin))
  log("  view top = " .. tostring(textWithMargin.getTop()) .. " (期望 " .. dp(24) .. ")")
end)

local col2 = LinearLayout(activity)
col2.setOrientation(LinearLayout.VERTICAL)
local wrapper = loadlayout({
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "wrap",
  MaterialTextView,
  layout_width = "match",
  layout_height = "wrap",
  text = "内联子视图",
  textSize = "14sp",
  layout_marginTop = "20dp",
})
col2.addView(wrapper)
measureIn(col2, screenWidth)
log("")
log("[C] inline child view with layout_marginTop")
pcall(function()
  local child = wrapper.getChildAt(0)
  local lp = child.getLayoutParams()
  log("  LP = " .. tostring(lp.getClass().getName()) .. " top=" .. tostring(lp.topMargin))
  log("  child top = " .. tostring(child.getTop()) .. " (期望 " .. dp(20) .. ")")
end)

log("")
log("[D] card into FrameLayout")
pcall(function()
  local frame = FrameLayout(activity)
  local card = kit.card({ kit.text("frame 里的卡片", { size = 14 }) }, {
    marginHorizontal = 16, marginTop = 10,
  })
  frame.addView(card)
  measureIn(frame, screenWidth)
  local lp = card.getLayoutParams()
  log("  OK  LP = " .. tostring(lp.getClass().getName())
    .. " left=" .. tostring(lp.leftMargin))
  log("  measured = " .. tostring(card.getMeasuredWidth()) .. "px")
end)

flush()
print("probe_margin2 done -> " .. OUT)
