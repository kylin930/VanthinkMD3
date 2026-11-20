-- v13：定位持续重绘的最小控件组合（卡片是否可点击 / 徽标 / 进度环）。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_card.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local rawPrint = print
print = function() end

local draws = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() draws = draws + 1 end,
})

local kit = require "app.ui.kit"
local colors = require("app.ui.theme").colors()

local function content()
  return {
    kit.text("作业 1", { size = 16, bold = true }),
    kit.spacer(6),
    kit.text("高一(3)班 · 普通模式", { size = 12, color = colors.onSurfaceVariant }),
  }
end

local cases = {
  { label = "card 无 onClick", build = function() return kit.card(content(), { padding = 16 }) end },
  { label = "card 有 onClick", build = function()
    return kit.card(content(), { padding = 16, onClick = function() end })
  end },
  { label = "card 有 onClick + marginTop", build = function()
    return kit.card(content(), { padding = 16, marginTop = 8, marginBottom = 4, onClick = function() end })
  end },
  { label = "card 有 onClick + badge", build = function()
    local children = content()
    children[#children + 1] = kit.badge("已完成", { background = colors.tertiaryContainer,
      color = colors.onTertiaryContainer })
    return kit.card(children, { padding = 16, onClick = function() end })
  end },
  { label = "card 有 onClick + spinner", build = function()
    local children = content()
    children[#children + 1] = kit.spinner(20)
    return kit.card(children, { padding = 16, onClick = function() end })
  end },
  { label = "listItem 有 onClick", build = function()
    return kit.listItem({ title = "主题设置", subtitle = "跟随系统", showChevron = true,
      onClick = function() end })
  end },
  { label = "button 有 onClick", build = function()
    return kit.button("加载更多", { onClick = function() end })
  end },
  { label = "iconButton 有 onClick", build = function()
    return kit.iconButton("refresh", { onClick = function() end })
  end },
}

local index = 0

local function runCase()
  index = index + 1
  local item = cases[index]
  if item == nil then
    log("=== 结束 ===")
    flush()
    print = rawPrint
    rawPrint("card diag done")
    return
  end
  local ok, view = pcall(item.build)
  if not ok or view == nil then
    log("FAIL " .. item.label .. " :: " .. tostring(view):sub(1, 120))
    flush()
    runCase()
    return
  end
  activity.setContentView(view)
  activity.delay(1200, function()
    pcall(function() view.getViewTreeObserver().addOnDrawListener(listener) end)
    draws = 0
    activity.delay(2000, function()
      log(string.format("%-32s %3d 帧 / 2 秒", item.label, draws))
      flush()
      runCase()
    end)
  end)
end

runCase()
