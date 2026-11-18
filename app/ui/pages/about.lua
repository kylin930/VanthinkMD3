-- 关于 VanthinkMD3

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local router = require "app.router"
local config = require "app.config"

local M = {}

function M.create()
  local colors = theme.colors()
  local shell = kit.scrollPage({})
  local sub = router.subPage({ title = "关于", content = shell.root })

  shell.add(kit.spacer(8))
  shell.add(kit.card({
    kit.row({
      kit.colorDot(56, colors.primaryContainer, colors.primary),
      kit.column({
        kit.text("VanthinkMD3", {
          size = kit.TYPOGRAPHY.headline,
          color = colors.onSurface,
          bold = true,
        }),
        kit.spacer(4),
        kit.text("在线助教学生端 · 原生 Android 重构版", {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
        }),
      }, { width = "0dp", weight = 1, marginStart = 16 }),
    }, { width = "match" }),
    kit.spacer(14),
    kit.text(string.format("版本 %s", config.APP_VERSION), {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }),
  }, { marginHorizontal = 16, padding = 18 }))

  shell.add(kit.sectionTitle("技术说明"))
  shell.add(kit.card({
    kit.text(
      "本应用使用 Lua 编写，运行在 NeLuaJ+ 运行时之上，界面全部为 Android 原生 View"
      .. "（Material Components 3），不含 WebView、HTML/CSS/JS 前端框架。"
      .. "网络请求通过 OkHttp 在后台线程执行，图标与图表由原生 Canvas 绘制。",
      { size = kit.TYPOGRAPHY.body, color = colors.onSurface, width = "match" }),
  }, { marginHorizontal = 16, padding = 16 }))

  shell.add(kit.sectionTitle("数据来源"))
  shell.add(kit.card({
    kit.text("业务数据来自官方接口：", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }),
    kit.spacer(4),
    kit.text(config.API_BASE, {
      size = kit.TYPOGRAPHY.label,
      color = colors.primary,
      width = "match",
    }),
    kit.spacer(10),
    kit.text(
      "Auth 迁移与版本说明使用原项目沿用的第三方中转服务（" .. config.THIRD_PARTY.sourceHost
      .. "），属于可选能力；不可用时不影响作业、通知、统计功能。",
      { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
  }, { marginHorizontal = 16, padding = 16 }))

  shell.add(kit.sectionTitle("开源与致谢"))
  shell.add(kit.card({
    kit.text(
      "感谢原 Web 版本（Vanthink WebMDUI2）提供的功能原型。"
      .. "本应用为独立重写实现，采用 Material Design 3 设计语言重新设计了信息架构与交互。",
      { size = kit.TYPOGRAPHY.body, color = colors.onSurface, width = "match" }),
  }, { marginHorizontal = 16, padding = 16 }))

  shell.add(kit.spacer(24))
  return { key = "about", view = sub.root }
end

return M
