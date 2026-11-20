-- v0.2.3 诊断：导航图标身份 + 我的页面 40dp 视图
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_v023.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(out, "\n")) end) end
flush()

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
local icons = require "app.ui.icons"
local state = require "app.state"
pcall(function() theme.bootstrap() end)
local colors = theme.colors()
local dp = theme.dp

local System = luajava.bindClass("java.lang.System")

local function hashCode(value)
  if value == nil then return "nil" end
  local ok, id = pcall(function() return System.identityHashCode(value) end)
  if ok then return tostring(id) end
  return "err"
end

local function bitmapOf(drawable)
  local ok, bitmap = pcall(function() return drawable.getBitmap() end)
  if ok then return bitmap end
  return nil
end

local homeworkService = require "app.services.homework"
homeworkService.fetchList = function(opts, cb)
  cb(true, { list = {}, total = 0, page = 1, hasMore = false })
end
require("app.services.notice").fetchList = function(opts, cb)
  cb(true, { list = {}, count = 0, page = 1, hasMore = false })
end
require("app.services.statistics").fetchReport = function(opts, cb)
  cb(true, { daily = {} })
end
require("app.services.auth").fetchAccount = function(cb) cb(true) end
require("app.services.update").fetch = function(cb) cb(false, "skip") end
pcall(function() state.setToken("probe_token") end)
pcall(function() state.setAccount({ id = 1, nickname = "probe" }) end)

local shell = require "app.ui.shell"
pcall(function() shell.init() end)
pcall(function() shell.showMain() end)

local nav = shell.bottomNav
log("nav = " .. tostring(nav))
if nav ~= nil then
  local menu = nav.getMenu()
  pcall(function() nav.setSelectedItemId(1) end)
  local filled = icons.get("assignment", 24, colors.onSecondaryContainer)
  local outline = icons.get("assignment_outline", 24, colors.onSurfaceVariant)
  local itemIcon = menu.findItem(1).getIcon()
  log("cached filled  bitmap=" .. hashCode(bitmapOf(filled)))
  log("cached outline bitmap=" .. hashCode(bitmapOf(outline)))
  log("menu item1 class=" .. tostring(itemIcon and itemIcon.getClass().getName()))
  log("menu item1 bitmap=" .. hashCode(bitmapOf(itemIcon)))
  log("item1 == filled ? " .. tostring(hashCode(itemIcon) == hashCode(filled))
    .. "  item1 == outline ? " .. tostring(hashCode(itemIcon) == hashCode(outline)))
  pcall(function()
    local b = itemIcon.getBounds()
    log("bounds = " .. b.width() .. "x" .. b.height() .. " (dp24=" .. dp(24) .. ")")
  end)
  log("onSecondaryContainer=" .. tostring(colors.onSecondaryContainer))
  log("onSecondaryContainer unsigned=" .. tostring(theme.unsigned(colors.onSecondaryContainer)))
end

activity.delay(600, function()
  local router = require "app.router"
  router.showTab("profile")
  activity.delay(600, function()
    local view = router.current and router.current.view
    log("")
    log("[profile 40dp views]")
    local function walk(node, depth)
      if node == nil or depth > 40 then return end
      local okW, w = pcall(function() return node.getMeasuredWidth() end)
      local okH, h = pcall(function() return node.getMeasuredHeight() end)
      if okW and okH and math.abs(w - dp(40)) <= 2 and math.abs(h - dp(40)) <= 2 then
        local cls = ""
        pcall(function() cls = node.getClass().getName() end)
        local text = ""
        pcall(function()
          local value = node.getText()
          if value ~= nil then text = tostring(value) end
        end)
        log(string.format("  40dp  %s  text='%s' depth=%d", cls, text:sub(1, 24), depth))
      end
      local okCount, count = pcall(function() return node.getChildCount() end)
      if okCount then
        for index = 0, count - 1 do
          local okChild, child = pcall(function() return node.getChildAt(index) end)
          if okChild then walk(child, depth + 1) end
        end
      end
    end
    if view ~= nil then walk(view, 0) end
    flush()
  end)
end)

flush()
print("probe_v023 done -> " .. OUT)
