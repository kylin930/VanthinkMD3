-- 我的页残留重绘下钻：逐层隐藏子视图，找出仍在持续重绘的控件。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_profile.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local View = luajava.bindClass("android.view.View")

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"
local router = require "app.router"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() state.setAccount({ id = 12345, nickname = "测试同学" }) end)
pcall(function() shell.showMain() end)
pcall(function() router.showTab("profile") end)

local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})
pcall(function() shell.root.getViewTreeObserver().addOnDrawListener(listener) end)

local function childCount(view)
  local ok, count = pcall(function() return view.getChildCount() end)
  if ok and type(count) == "number" then return count end
  return 0
end

local function describe(view)
  return tostring(view.getClass().getSimpleName()) .. "(" .. view.getWidth() .. "x" .. view.getHeight() .. ")"
end

local function drill(node, depth, done)
  local count = childCount(node)
  if depth > 8 or count == 0 then
    log(string.rep(" ", depth) .. "命中：" .. describe(node))
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
        log(string.rep(" ", depth) .. "无子视图降低帧数：" .. describe(node))
        flush()
        done()
        return
      end
      log(string.rep(" ", depth) .. "深入：" .. describe(best.view) .. "（" .. best.frames .. " 帧）")
      flush()
      drill(best.view, depth + 1, done)
      return
    end
    local child = node.getChildAt(index - 1)
    if child == nil or child.getVisibility() == View.GONE then nextChild(); return end
    pcall(function() child.setVisibility(View.INVISIBLE) end)
    draws = 0
    activity.delay(800, function()
      local frames = draws
      pcall(function() child.setVisibility(View.VISIBLE) end)
      log(string.rep(" ", depth) .. string.format("child %d %s -> %d 帧", index - 1, describe(child), frames))
      flush()
      if best == nil or frames < best.frames then best = { view = child, frames = frames } end
      nextChild()
    end)
  end
  nextChild()
end

activity.delay(3000, function()
  draws = 0
  activity.delay(1500, function()
    log("基线 " .. draws .. " 帧 / 1.5 秒")
    flush()
    drill(shell.root, 0, function()
      log("=== 结束 ===")
      flush()
      print = rawPrint
      rawPrint("profile drill done")
    end)
  end)
end)
