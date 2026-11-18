-- 测试 G: 验证 Insets 回调里 setPadding 是否引发布局循环（闪烁根因）
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoG.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end

local rawPrint = print
print = function() end

local ViewCompat = luajava.bindClass("androidx.core.view.ViewCompat")
local WindowInsetsCompat = luajava.bindClass("androidx.core.view.WindowInsetsCompat")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")

local root = loadlayout({
  LinearLayout,
  orientation = "vertical",
  layout_width = "match",
  layout_height = "match",
  {
    MaterialTextView,
    layout_width = "match",
    layout_height = "wrap",
    text = "Insets 循环验证",
    textSize = "16sp",
  },
})
activity.setContentView(root)
flush()

local countPlain = 0
local countPadding = 0

-- 阶段一：回调里只计数，不修改任何布局属性
local ok1, err1 = pcall(function()
  ViewCompat.setOnApplyWindowInsetsListener(root, function(view, insets)
    countPlain = countPlain + 1
    return insets
  end)
  ViewCompat.requestApplyInsets(root)
end)
log("阶段一挂载 ok=" .. tostring(ok1) .. " err=" .. tostring(err1))
flush()

activity.delay(2000, function()
  log("阶段一（不设 padding）2 秒内分发次数 = " .. countPlain)
  flush()

  -- 阶段二：回调里设置 padding（复现旧实现）
  local ok2, err2 = pcall(function()
    ViewCompat.setOnApplyWindowInsetsListener(root, function(view, insets)
      countPadding = countPadding + 1
      local bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
      view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
      return insets
    end)
    ViewCompat.requestApplyInsets(root)
  end)
  log("阶段二挂载 ok=" .. tostring(ok2) .. " err=" .. tostring(err2))
  flush()

  activity.delay(2000, function()
    log("阶段二（设 padding）2 秒内分发次数 = " .. countPadding)
    log("")
    if countPadding > countPlain * 20 and countPadding > 100 then
      log("RESULT: 确认存在布局循环（设 padding 后分发次数暴涨）")
    else
      log("RESULT: 未出现明显循环（plain=" .. countPlain .. " padding=" .. countPadding .. "）")
    end
    flush()
    print = rawPrint
    rawPrint("iso G done")
  end)
end)
