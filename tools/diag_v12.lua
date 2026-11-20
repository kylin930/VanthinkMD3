-- v12：用桩数据跑真实页面，量化「数据渲染完成后」的静止帧率，定位持续重绘来源。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_main.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local draws = 0
local layouts = 0
local drawListener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})
local layoutListener = luajava.createProxy("android.view.ViewTreeObserver$OnGlobalLayoutListener", {
  onGlobalLayout = function() layouts = layouts + 1 end,
})

-- 桩：作业列表恒返回 6 条，通知列表恒返回 4 条
local homeworkStub = function(opts, callback)
  local list = {}
  for i = 1, 6 do
    list[i] = {
      id = 1000 + i,
      name = "作业 " .. i,
      vanclass_name = "高一(3)班",
      type = { name = "普通模式" },
      testbank_count = 12,
      completion_rate = i * 10,
      created_at = "2026/08/0" .. i,
      description = "描述文本",
    }
  end
  callback(true, { list = list, total = 6, page = 1, hasMore = false })
end

local noticeStub = function(opts, callback)
  local list = {}
  for i = 1, 4 do
    list[i] = {
      id = 2000 + i,
      content = "通知内容 " .. i,
      created_at = "2026/08/0" .. i,
      has_read = i % 2,
      sender = { nickname = "张老师" },
    }
  end
  callback(true, { list = list, count = 4, hasMore = false })
end

require("app.services.homework").fetchList = homeworkStub
require("app.services.notice").fetchList = noticeStub

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"
local router = require "app.router"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() shell.showMain() end)
-- 主界面壳已挂载，再挂监听（内容随时可能被替换）
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(drawListener) end)
pcall(function() shell.root.getViewTreeObserver().addOnGlobalLayoutListener(layoutListener) end)

local function measure(label, nextFn)
  draws, layouts = 0, 0
  activity.delay(2500, function()
    log(string.format("[%s] 2.5 秒：绘制 %d 帧，布局 %d 次", label, draws, layouts))
    flush()
    nextFn()
  end)
end

local sequence = {
  { "作业页(桩数据)", function() router.showTab("homework") end },
  { "通知页(桩数据)", function() router.showTab("notifications") end },
  { "统计页", function() router.showTab("statistics") end },
  { "我的页", function() router.showTab("profile") end },
  { "切回作业页", function() router.showTab("homework") end },
}

local index = 0
local function nextCase()
  index = index + 1
  local item = sequence[index]
  if item == nil then
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("diag v12 done")
    return
  end
  local ok, err = pcall(item[2])
  if not ok then
    log("FAIL " .. item[1] .. " :: " .. tostring(err):sub(1, 160))
    flush()
    nextCase()
    return
  end
  measure(item[1], nextCase)
end

activity.delay(2000, nextCase)
