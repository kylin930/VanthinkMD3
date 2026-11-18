-- 对照组 F: 只挂生命周期 + 每秒采样，不加载任何应用代码
-- 若同样在约 6 秒被销毁，说明销毁来自测试工具而非应用代码
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoF.txt"

local function append(text)
  local previous = ""
  pcall(function() previous = LFU.read(OUT) or "" end)
  pcall(function() LFU.writeOrCreate(OUT, previous .. tostring(text) .. "\n") end)
end

local rawPrint = print
print = function() end

append("SCRIPT_START " .. tostring(activity))

function onCreate() append("  onCREATE " .. tostring(activity)) end
function onStart() append("  onStart " .. tostring(activity)) end
function onResume() append("  onResume " .. tostring(activity)) end
function onPause() append("  onPause " .. tostring(activity)) end
function onStop() append("  onStop " .. tostring(activity)) end
function onDestroy() append("  onDestroy " .. tostring(activity)) end

-- 只显示一个最简单的视图，等价于模板空页面
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
activity.setContentView(loadlayout({
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    MaterialTextView,
    layout_width = "match",
    layout_height = "wrap",
    text = "对照组 F",
    textSize = "16sp",
  },
}))
append("AFTER_SETCONTENTVIEW")

for index = 1, 10 do
  activity.delay(index * 1000, function()
    append(string.format("  TICK_%ds alive=%s", index, tostring(activity)))
  end)
end
