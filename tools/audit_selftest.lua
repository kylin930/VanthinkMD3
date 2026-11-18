-- 审计机制自检：故意使用无效属性，验证 print 劫持能否捕获 loadlayout 的告警。
-- 若捕获不到，则上一轮“0 问题”的结论不可信，需更换拦截方式。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_audit_selftest.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
local captured = {}
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  captured[#captured + 1] = table.concat(parts, "\t")
end

local HorizontalScrollView = luajava.bindClass("android.widget.HorizontalScrollView")

do
  captured = {}
  local ok, err = pcall(function()
    loadlayout({ HorizontalScrollView, layout_width = "match", layout_height = "wrap" })
  end)
  log("有效属性 loadlayout ok=" .. tostring(ok) .. " err=" .. tostring(err))
  log("捕获日志条数=" .. #captured)
  for _, text in ipairs(captured) do
    log("  [有效] " .. tostring(text):gsub("\n", " "):sub(1, 300))
  end
  flush()
end

do
  captured = {}
  local ok, err = pcall(function()
    loadlayout({
      HorizontalScrollView,
      layout_width = "match",
      layout_height = "wrap",
      scrollbars = "none",
      totallyInvalidAttr = "x",
    })
  end)
  log("无效属性 loadlayout ok=" .. tostring(ok) .. " err=" .. tostring(err))
  log("捕获日志条数=" .. #captured)
  for _, text in ipairs(captured) do
    log("  [无效] " .. tostring(text):gsub("\n", " "):sub(1, 300))
  end
  flush()
end

print = rawPrint
log("=== 自检结束 ===")
flush()
print("selftest done")
