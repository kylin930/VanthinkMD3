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
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

  shell.add(kit.sectionTitle("技术说明"))
  shell.add(kit.card({
    kit.text(
      "本应用使用 Lua 编写，运行在 NeLuaJ+ 运行时之上，界面全部为 Android 原生 View"
      .. "（Material Components 3），不含 WebView、HTML/CSS/JS 前端框架。"
      .. "网络请求通过 OkHttp 在后台线程执行，图标与图表由原生 Canvas 绘制。",
      { size = kit.TYPOGRAPHY.body, color = colors.onSurface, width = "match" }),
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

  shell.add(kit.sectionTitle("项目来源"))
  shell.add(kit.card({
    kit.text("VanthinkWebMDUI2", {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      bold = true,
    }),
    kit.spacer(4),
    kit.text(
      "项目的早期 Web 实现，使用 MDUI2 构建，完成了核心业务功能与交互设计。",
      { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
    kit.spacer(12),
    kit.text("VanthinkMD3", {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      bold = true,
    }),
    kit.spacer(4),
    kit.text(
      "面向 Android 平台的原生重构版本，基于 NeLuaJ+ 开发，"
      .. "采用 Android 原生 View 与 Material Design 3 重新构建界面和应用架构。",
      { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
    kit.spacer(12),
    kit.text(
      "两个项目属于同一产品的不同技术实现。VanthinkMD3 在继承原有业务经验的基础上，"
      .. "对技术架构、界面和交互进行了独立重写。",
      { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

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
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

  shell.add(kit.sectionTitle("开源与致谢"))
  shell.add(kit.card({
    kit.text(
      "感谢 NeLuaJ+、AndroidX、Material Components for Android 等实际使用的开源项目及开发社区。",
      { size = kit.TYPOGRAPHY.body, color = colors.onSurface, width = "match" }),
    kit.spacer(10),
    kit.text(
      "其中 NeLuaJ+ 提供 Lua 运行时与打包能力，AndroidX 提供 Activity、Insets、"
      .. "下拉刷新与滚动容器，Material Components for Android 提供 MD3 组件与转场动画，"
      .. "网络请求使用运行时内置的 OkHttp。",
      { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
  }, { marginHorizontal = kit.SPACING.pageHorizontal, padding = kit.SPACING.cardPadding }))

  shell.add(kit.spacer(24))
  return { key = "about", view = sub.root }
end

return M
