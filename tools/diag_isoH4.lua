-- 测试 H3: 量化布局频率，判断界面是否持续重排
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_isoH.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end

local rawPrint = print
print = function() end

require "app.ui.theme".bootstrap()
local shell = require "app.ui.shell"
shell.init()
shell.start()
log("已启动 mode=" .. tostring(shell.mode))
flush()

local drawCount = 0
local listener = luajava.createProxy("android.view.ViewTreeObserver$OnDrawListener", {
  onDraw = function() drawCount = drawCount + 1 end,
})

local okRoot = pcall(function()
  shell.root.getViewTreeObserver().addOnDrawListener(listener)
end)
log("挂载 OnDrawListener=" .. tostring(okRoot))
flush()

local at1 = 0

activity.delay(1000, function()
  at1 = drawCount
end)

activity.delay(3000, function()
  log("阶段一(登录页) 0-1s=" .. at1 .. "  1-3s=" .. (drawCount - at1))
  flush()

  local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
  local colors = require("app.ui.theme").colors()

  local container = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = colors.surface,
    padding = "24dp",
    {
      MaterialTextField,
      layout_width = "match",
      layout_height = "wrap",
      hint = "手机号",
      singleLine = true,
      inputType = "phone",
      style = MaterialStyle.Widget_Material3_TextInputLayout_OutlinedBox,
      tintColor = colors.primary,
    },
  })
  activity.setContentView(container)
  log("阶段二 仅 MaterialTextField")
  drawCount = 0
  pcall(function()
    container.getViewTreeObserver().addOnDrawListener(listener)
  end)
  flush()

  local b1 = 0
  activity.delay(1000, function()
    b1 = drawCount
  end)

  activity.delay(3000, function()
    log("阶段二 0-1s=" .. b1 .. "  1-3s=" .. (drawCount - b1))
    flush()

    local EditText = luajava.bindClass("android.widget.EditText")
    local plain = loadlayout({
      LinearLayout,
      orientation = "vertical",
      layout_width = "match",
      layout_height = "match",
      BackgroundColor = colors.surface,
      padding = "24dp",
      {
        EditText,
        layout_width = "match",
        layout_height = "wrap",
        hint = "手机号",
        singleLine = true,
        inputType = "phone",
        textSize = "16sp",
      },
    })
    activity.setContentView(plain)
    log("阶段三 原生 EditText")
    drawCount = 0
    pcall(function()
      plain.getViewTreeObserver().addOnDrawListener(listener)
    end)
    flush()

    local c1 = 0
    activity.delay(1000, function()
      c1 = drawCount
    end)

    activity.delay(3000, function()
      log("阶段三 0-1s=" .. c1 .. "  1-3s=" .. (drawCount - c1))
      log("判定：无交互每秒超过 10 次即持续重绘")
      flush()
      print = rawPrint
      rawPrint("draw diag done")
    end)
  end)
end)
