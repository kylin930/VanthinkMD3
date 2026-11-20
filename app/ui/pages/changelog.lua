-- 更新日志：展示服务端返回的版本说明（新增 / 优化 / 修复 / 备注）。
-- 更新服务位于第三方域名，属于可选能力：失败只给出提示，不影响应用使用。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local updateService = require "app.services.update"

local M = {}

local function listCard(title, items, colors, accentBackground, accentColor)
  if #items == 0 then return nil end
  local children = {
    kit.badge(title, { background = accentBackground, color = accentColor }),
    kit.spacer(10),
  }
  for _, item in ipairs(items) do
    children[#children + 1] = kit.row({
      kit.text("•", { size = kit.TYPOGRAPHY.body, color = accentColor }),
      kit.text(item, {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurface,
        width = "0dp",
        weight = 1,
        marginStart = 8,
      }),
    }, { width = "match", gravity = "top" })
    children[#children + 1] = kit.spacer(6)
  end
  return kit.card(children, { marginHorizontal = 16, marginTop = 8, padding = 16 })
end

function M.renderChangelog(shell, data)
  local colors = theme.colors()
  shell.clear()
  shell.add(kit.spacer(8))
  shell.add(kit.card({
    kit.text(tostring(data.version or "未知版本"), {
      size = kit.TYPOGRAPHY.headline,
      color = colors.onSurface,
      bold = true,
    }),
    kit.spacer(6),
    kit.text("更新时间：" .. tostring(data.updateTime or "未指定"), {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }),
  }, { marginHorizontal = 16, padding = 18 }))

  local added = listCard("新增", data.added or {}, colors,
    colors.primaryContainer, colors.onPrimaryContainer)
  if added ~= nil then shell.add(added) end
  local improved = listCard("优化", data.improved or {}, colors,
    colors.secondaryContainer, colors.onSecondaryContainer)
  if improved ~= nil then shell.add(improved) end
  local fixed = listCard("修复", data.fixed or {}, colors,
    colors.tertiaryContainer, colors.onTertiaryContainer)
  if fixed ~= nil then shell.add(fixed) end

  if data.note ~= nil and tostring(data.note) ~= "" then
    shell.add(kit.card({
      kit.text("备注", {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
        bold = true,
      }),
      kit.spacer(6),
      kit.text(tostring(data.note), {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurface,
        width = "match",
      }),
    }, { marginHorizontal = 16, marginTop = 8, padding = 16 }))
  end
  shell.add(kit.spacer(24))
end

-- 独立页面
function M.create(manual)
  local colors = theme.colors()
  local shell = kit.scrollPage({
    onRefresh = function() load() end,
  })
  local sub = router.subPage({ title = "更新日志", content = shell.root })
  local page = { key = "changelog", view = sub.root }

  function load()
    shell.clear()
    shell.add(kit.row({
      kit.spinner(22),
      kit.text("正在获取版本信息…", {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurfaceVariant,
        marginStart = 12,
      }),
    }, { width = "match", padding = 28, gravity = "center" }))

    updateService.fetch(function(ok, dataOrMessage)
      shell.setRefreshing(false)
      if not ok then
        shell.clear()
        shell.add(kit.stateView({
          icon = "cloud_off",
          title = "无法加载更新日志",
          message = tostring(dataOrMessage) .. "。更新服务由第三方提供，不可用不影响应用使用。",
          actionLabel = "重试",
          actionIcon = "refresh",
          onAction = function() load() end,
        }))
        return
      end
      M.renderChangelog(shell, dataOrMessage)
    end)
  end

  page.onShow = load
  load()
  return page
end

-- 弹窗形式（自动检测到新版本时使用）
function M.showDialog(data, manual)
  local colors = theme.colors()
  local content = kit.column({}, { width = "match", padding = 8 })
  local maxLines = 12
  local lineCount = 0

  local function add(text, opts)
    if lineCount >= maxLines then return end
    content.addView(kit.text(text, opts))
    content.addView(kit.spacer(4))
    lineCount = lineCount + 1
  end

  add("版本：" .. tostring(data.version), {
    size = kit.TYPOGRAPHY.body,
    color = colors.onSurface,
    bold = true,
  })
  add("更新时间：" .. tostring(data.updateTime or "未指定"), {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
  })
  for _, item in ipairs(data.added or {}) do
    add("· " .. item, { size = kit.TYPOGRAPHY.label, color = colors.onSurface })
  end
  for _, item in ipairs(data.improved or {}) do
    add("· " .. item, { size = kit.TYPOGRAPHY.label, color = colors.onSurface })
  end
  for _, item in ipairs(data.fixed or {}) do
    add("· " .. item, { size = kit.TYPOGRAPHY.label, color = colors.onSurface })
  end
  if lineCount >= maxLines then
    content.addView(kit.text("…更多内容请在“更新日志”页面查看", {
      size = kit.TYPOGRAPHY.label,
      color = colors.outline,
    }))
  end

  dialogs.custom({
    title = manual and "更新日志" or "发现新版本",
    view = content,
    positiveLabel = "知道了",
    onPositive = function()
      if not manual then
        dialogs.snackbar("可以在“我的 → 更新日志”中再次查看")
      end
    end,
    negativeLabel = "查看完整",
    onNegative = function()
      router.push(M.create(true))
    end,
  })
end

return M
