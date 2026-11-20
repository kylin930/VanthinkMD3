-- 统计页切回后状态诊断（开发期工具）
-- 目的：定位「统计 tab 切走再切回后，卡片数变少、图表宽度为 0」的原因。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_stats.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(out, "\n")) end) end
flush()

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
local state = require "app.state"
pcall(function() theme.bootstrap() end)

require("app.services.homework").fetchList = function(opts, cb)
  cb(true, { list = {}, total = 0, page = 1, hasMore = false })
end
require("app.services.notice").fetchList = function(opts, cb)
  cb(true, { list = {}, count = 0, page = 1, hasMore = false })
end
require("app.services.statistics").fetchReport = function(opts, cb)
  local daily = {}
  for day = 1, 20 do
    daily[day] = { day = string.format("2026/08/%02d", day), score = day * 7, time = day * 3 }
  end
  cb(true, {
    practice = { count = 128, avg = 12.5, monthAvg = 9 },
    exercise = { count = 1024, avg = 96.4, monthAvg = 88 },
    days = { count = 21, avg = 32.5, monthAvg = 28 },
    photo = { count = 7, avg = 1.2, monthAvg = 1 },
    pl = { startTime = "2026/01/05 08:00:00", totalTime = 1520, avgTime = 46 },
    daily = daily,
  })
end
require("app.services.auth").fetchAccount = function(cb) cb(true) end
require("app.services.update").fetch = function(cb) cb(false, "skip") end
pcall(function() state.setToken("probe_token") end)
pcall(function() state.setAccount({ id = 1, nickname = "probe" }) end)

local shell = require "app.ui.shell"
local router = require "app.router"
local motion = require "app.ui.motion"
pcall(function() shell.init() end)
pcall(function() shell.showMain() end)

local function childCount(view)
  local ok, count = pcall(function() return view.getChildCount() end)
  if ok then return count end
  return -1
end

local function walk(node, fn, depth)
  depth = depth or 0
  if node == nil or depth > 40 then return end
  fn(node, depth)
  for index = 0, childCount(node) - 1 do
    local ok, child = pcall(function() return node.getChildAt(index) end)
    if ok then walk(child, fn, depth + 1) end
  end
end

local function classOf(view)
  local name = ""
  pcall(function() name = view.getClass().getName() end)
  return name
end

local function dump(tag)
  log("")
  log("---- " .. tag)
  log("  kit.windowWidthDp() = " .. tostring(kit.windowWidthDp()))
  log("  router.currentKey = " .. tostring(router.currentKey))
  log("  container childCount = " .. childCount(router.container))
  local page = router.current
  if page == nil or page.view == nil then log("  current.view = nil") flush() return end
  log("  page key = " .. tostring(page.key)
    .. "  loaded=" .. tostring(page.loaded)
    .. "  data=" .. (page.data ~= nil and "yes" or "nil"))
  log("  view measured = " .. tostring(page.view.getMeasuredWidth()) .. "x"
    .. tostring(page.view.getMeasuredHeight()))

  local cards, charts, index = {}, {}, 0
  walk(page.view, function(node)
    local cls = classOf(node)
    if string.find(cls, "MaterialCardView", 1, true) ~= nil then
      index = index + 1
      cards[#cards + 1] = string.format("#%d %dx%d L=%d T=%d R=%d B=%d",
        index, node.getMeasuredWidth(), node.getMeasuredHeight(),
        node.getLeft(), node.getTop(), node.getRight(), node.getBottom())
    end
    if string.find(cls, "android.widget.ImageView", 1, true) ~= nil then
      charts[#charts + 1] = string.format("%dx%d", node.getMeasuredWidth(),
        node.getMeasuredHeight())
    end
  end)
  log("  cards = " .. #cards)
  for _, line in ipairs(cards) do log("    " .. line) end
  log("  imageViews = " .. #charts)
  for _, line in ipairs(charts) do log("    " .. line) end
  flush()
end

activity.delay(600, function()
  dump("启动后（作业页）")
  router.showTab("statistics")
  activity.delay(900, function()
    dump("第一次进入统计页")
    router.showTab("profile")
    activity.delay(700, function()
      dump("切到我的")
      router.showTab("statistics")
      activity.delay(900, function()
        dump("第二次进入统计页")
        router.showTab("homework")
        router.showTab("notifications")
        router.showTab("profile")
        router.showTab("statistics")
        activity.delay(1200, function()
          dump("快速连点后回到统计页")
          log("")
          log("motion mode = " .. tostring(motion.mode))
          flush()
        end)
      end)
    end)
  end)
end)

flush()
print("probe_stats done -> " .. OUT)
