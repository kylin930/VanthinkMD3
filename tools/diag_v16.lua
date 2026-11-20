-- v16：自动下钻定位持续重绘视图（临时诊断脚本）
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_drill.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local View = luajava.bindClass("android.view.View")

local homeworkStub = function(opts, callback)
  local list = {}
  for i = 1, 2 do
    list[i] = {
      id = 1000 + i, name = "作业 " .. i, vanclass_name = "高一(3)班",
      type = { name = "普通模式" }, testbank_count = 12,
      completion_rate = i * 30, created_at = "2026/08/0" .. i,
    }
  end
  callback(true, { list = list, total = 2, page = 1, hasMore = false })
end
require("app.services.homework").fetchList = homeworkStub

local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() shell.showMain() end)
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(listener) end)

local function childCount(view)
  local ok, count = pcall(function() return view.getChildCount() end)
  if ok and type(count) == "number" then return count end
  return 0
end

local function measure(ms, nextFn)
  draws = 0
  activity.delay(ms, function() nextFn(draws) end)
end

local function describe(view)
  local name = tostring(view.getClass().getSimpleName())
  local parentOk, parent = pcall(function() return view.getParent() end)
  if parentOk and parent ~= nil then
    local ok2, parentName = pcall(function()
      return tostring(luajava.cast(parent, "android.view.View").getClass().getSimpleName())
    end)
    if ok2 then name = tostring(parentName) .. ">" .. name end
  end
  return name .. "(" .. view.getWidth() .. "x" .. view.getHeight() .. ")"
end

local function drill(node, depth, done)
  if depth > 6 then
    log("达到最大深度，命中：" .. describe(node))
    flush()
    done()
    return
  end
  local count = childCount(node)
  if count == 0 then
    log("叶子命中：" .. describe(node))
    flush()
    done()
    return
  end
  local index = 0
  local best = nil
  local function nextChild()
    index = index + 1
    if index > count then
      if best == nil then
        log(string.rep(" ", depth) .. "无子视图能降低帧数，停在：" .. describe(node))
        flush()
        done()
        return
      end
      log(string.rep(" ", depth) .. "深入：" .. describe(best.view) .. "（隐藏后 " .. best.frames .. " 帧）")
      flush()
      drill(best.view, depth + 1, done)
      return
    end
    local child = node.getChildAt(index - 1)
    if child == nil or child.getVisibility() == View.GONE then
      nextChild()
      return
    end
    pcall(function() child.setVisibility(View.INVISIBLE) end)
    measure(700, function(frames)
      pcall(function() child.setVisibility(View.VISIBLE) end)
      log(string.rep(" ", depth) .. string.format("child %d %s -> %d 帧", index - 1,
        describe(child), frames))
      flush()
      if best == nil or frames < best.frames then
        best = { view = child, frames = frames }
      end
      nextChild()
    end)
  end
  nextChild()
end

activity.delay(3000, function()
  measure(1200, function(frames)
    log("基线 " .. frames .. " 帧 / 1.2 秒")
    flush()
    drill(shell.root, 0, function()
      log("=== 结束 ===")
      flush()
      print = rawPrint
      rawPrint("drill done")
    end)
  end)
end)
