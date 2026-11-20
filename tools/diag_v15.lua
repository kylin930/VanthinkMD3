-- v15：在 PreDraw 阶段遍历视图树，找出被标记为 dirty（触发重绘）的视图。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_dirty.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local View = luajava.bindClass("android.view.View")

local homeworkStub = function(opts, callback)
  local list = {}
  for i = 1, 4 do
    list[i] = {
      id = 1000 + i, name = "作业 " .. i, vanclass_name = "高一(3)班",
      type = { name = "普通模式" }, testbank_count = 12,
      completion_rate = i * 10, created_at = "2026/08/0" .. i,
    }
  end
  callback(true, { list = list, total = 4, page = 1, hasMore = false })
end
require("app.services.homework").fetchList = homeworkStub

local theme = require "app.ui.theme"
local state = require "app.state"
local shell = require "app.ui.shell"

pcall(function() theme.bootstrap() end)
pcall(function() shell.init() end)
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("diag_fake_token") end)
pcall(function() shell.showMain() end)

local dirtyCount = {}
local frames = 0

local function scan(view, out)
  local ok, dirty = pcall(function() return view.isDirty() end)
  if ok and dirty then
    local key = tostring(view.getClass().getSimpleName())
    local parentOk, parent = pcall(function() return view.getParent() end)
    if parentOk and parent ~= nil then
      local parentOk2, parentName = pcall(function()
        return luajava.cast(parent, "android.view.View").getClass().getSimpleName()
      end)
      if parentOk2 then key = tostring(parentName) .. ">" .. key end
    end
    if #view.getWidth() .. "x" .. view.getHeight() ~= nil then
      key = key .. " " .. view.getWidth() .. "x" .. view.getHeight()
    end
    out[#out + 1] = key
  end
  local childOk, count = pcall(function() return view.getChildCount() end)
  if childOk and type(count) == "number" and count > 0 then
    for i = 0, count - 1 do scan(view.getChildAt(i), out) end
  end
  return out
end

local listener = luajava.createProxy("android.view.ViewTreeObserver$OnPreDrawListener", {
  onPreDraw = function()
    frames = frames + 1
    if frames <= 40 and frames % 5 == 0 then
      local hits = scan(shell.root, {})
      for _, key in ipairs(hits) do
        dirtyCount[key] = (dirtyCount[key] or 0) + 1
      end
    end
    return true
  end,
})

activity.delay(3000, function()
  pcall(function() shell.root.getViewTreeObserver().addOnPreDrawListener(listener) end)
  frames = 0
  activity.delay(2000, function()
    log("2 秒内 preDraw 次数 = " .. frames)
    local sorted = {}
    for key, count in pairs(dirtyCount) do sorted[#sorted + 1] = { key = key, count = count } end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for i = 1, math.min(#sorted, 15) do
      log(string.format("%3d 次  %s", sorted[i].count, sorted[i].key))
    end
    pcall(function() shell.root.getViewTreeObserver().removeOnPreDrawListener(listener) end)
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("diag v15 done")
  end)
end)
