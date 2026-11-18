-- 属性有效性实测：textStyle 与 scrollbars 的真实行为
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_test_attrs.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
local Typeface = luajava.bindClass("android.graphics.Typeface")

do
  local ok, err = pcall(function()
    local view = loadlayout({
      MaterialTextView,
      layout_width = "wrap",
      layout_height = "wrap",
      text = "粗体测试",
      textSize = "16sp",
      textStyle = "bold",
    })
    local typeface = view.getTypeface()
    local isBold = false
    if typeface ~= nil then isBold = typeface.isBold() end
    log("textStyle=bold -> isBold=" .. tostring(isBold) .. " typeface=" .. tostring(typeface))
  end)
  if not ok then log("textStyle 测试异常: " .. tostring(err)) end
  flush()
end

do
  local ok, err = pcall(function()
    local view = loadlayout({
      MaterialTextView,
      layout_width = "wrap",
      layout_height = "wrap",
      text = "粗体测试2",
      textSize = "16sp",
    })
    view.setTypeface(Typeface.DEFAULT_BOLD)
    log("手动 setTypeface -> isBold=" .. tostring(view.getTypeface().isBold()))
  end)
  if not ok then log("setTypeface 测试异常: " .. tostring(err)) end
  flush()
end

do
  local ok, err = pcall(function()
    local view = loadlayout({
      MaterialTextView,
      layout_width = "wrap",
      layout_height = "wrap",
      text = "粗斜体",
      textStyle = "bold|italic",
    })
    local typeface = view.getTypeface()
    log("textStyle=bold|italic -> bold=" .. tostring(typeface and typeface.isBold())
      .. " italic=" .. tostring(typeface and typeface.isItalic()))
  end)
  if not ok then log("bold|italic 测试异常: " .. tostring(err)) end
  flush()
end

do
  local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")
  local ok, err = pcall(function()
    local view = loadlayout({
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
    })
    view.setHorizontalScrollBarEnabled(false)
    view.setVerticalScrollBarEnabled(false)
    log("HorizontalScrollView 关闭滚动条 -> enabled="
      .. tostring(view.isHorizontalScrollBarEnabled()))
  end)
  if not ok then log("HorizontalScrollView 测试异常: " .. tostring(err)) end
  flush()
end

log("=== 结束 ===")
flush()
print = rawPrint
print("attr test done")
