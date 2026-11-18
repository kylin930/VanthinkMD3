-- 闪烁诊断：包装全局 loadlayout，统计每个调用源的构建次数
-- 若某个源在几秒内被调用几十次，即为闪烁来源。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_flicker.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

-- 统计表
local counts = {}
local total = 0
local order = {}

local realLoadlayout = loadlayout

loadlayout = function(...)
  total = total + 1
  local info = debug.getinfo(2, "Sl")
  local source = "?"
  local line = "?"
  if info ~= nil then
    source = tostring(info.short_src or info.source or "?")
    line = tostring(info.currentline or "?")
  end
  local key = source .. ":" .. line
  if counts[key] == nil then
    counts[key] = 0
    order[#order + 1] = key
  end
  counts[key] = counts[key] + 1
  return realLoadlayout(...)
end

-- 统计 setContentView
local setContentCount = 0
local okSet, errSet = pcall(function()
  local realSet = activity.setContentView
  activity.setContentView = function(self, view)
    setContentCount = setContentCount + 1
    return realSet(self, view)
  end
end)
if not okSet then log("setContentView 包装失败: " .. tostring(errSet)) end

log("=== 开始启动 ===")
local ok, err = pcall(function()
  require "app.ui.theme".bootstrap()
  require "app.services.http".setTokenProvider(function()
    return require("app.state").token
  end)
  require "app.ui.shell".init()
  require "app.ui.shell".start()
end)
log("启动结果 ok=" .. tostring(ok) .. " err=" .. tostring(err))
log("setContentView 调用次数 = " .. setContentCount)
log("loadlayout 调用总数 = " .. total)
flush()

-- 3 秒后再采样一次，观察是否持续增长
activity.delay(3000, function()
  log("")
  log("=== 3 秒后 ===")
  log("setContentView 调用次数 = " .. setContentCount)
  log("loadlayout 调用总数 = " .. total)
  log("")
  log("=== 按调用源统计（次数降序）===")
  local sorted = {}
  for _, key in ipairs(order) do
    sorted[#sorted + 1] = { key = key, count = counts[key] }
  end
  table.sort(sorted, function(a, b) return a.count > b.count end)
  for _, item in ipairs(sorted) do
    log(string.format("%6d  %s", item.count, item.key))
  end
  flush()

  -- 再等 3 秒
  activity.delay(3000, function()
    log("")
    log("=== 6 秒后 ===")
    log("setContentView 调用次数 = " .. setContentCount)
    log("loadlayout 调用总数 = " .. total)
    if total > 0 then
      local top = sorted[1]
      if top ~= nil then
        log("最高频源: " .. top.key .. " -> " .. tostring(counts[top.key]) .. " 次")
      end
    end
    flush()
    print = rawPrint
    rawPrint("diag flicker done")
  end)
end)
