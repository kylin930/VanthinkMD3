-- 对话框与轻提示：统一使用 MaterialAlertDialogBuilder 与 Snackbar。
-- 危险操作统一走 confirm，由调用方显式传入确认文案。
-- 打开过的对话框会被记录，切换登录态时统一关闭，避免残留窗口堆积。

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"

local M = {}

local MaterialAlertDialogBuilder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
local Snackbar = luajava.bindClass("com.google.android.material.snackbar.Snackbar")

local openDialogs = {}

local function track(dialog)
  if dialog == nil then return dialog end
  -- 清理已关闭的引用，避免列表无限增长
  local alive = {}
  for _, item in ipairs(openDialogs) do
    local stillShowing = false
    pcall(function() stillShowing = item.isShowing() end)
    if stillShowing then alive[#alive + 1] = item end
  end
  alive[#alive + 1] = dialog
  openDialogs = alive
  return dialog
end

local function show(builder)
  local dialog = builder.create()
  track(dialog)
  dialog.show()
  return dialog
end

function M.dismissAll()
  for _, dialog in ipairs(openDialogs) do
    pcall(function() dialog.dismiss() end)
  end
  openDialogs = {}
end

function M.dismiss(dialog)
  if dialog == nil then return end
  pcall(function() dialog.dismiss() end)
end

function M.alert(title, message, positiveLabel)
  local builder = MaterialAlertDialogBuilder(activity)
    .setTitle(tostring(title or ""))
    .setPositiveButton(positiveLabel or "知道了", nil)
  if message ~= nil and tostring(message) ~= "" then
    builder.setMessage(tostring(message))
  end
  return show(builder)
end

-- onConfirm / onCancel 可为空函数
function M.confirm(opts)
  local o = opts or {}
  local builder = MaterialAlertDialogBuilder(activity)
    .setTitle(tostring(o.title or "确认"))
  if o.message ~= nil and tostring(o.message) ~= "" then
    builder.setMessage(tostring(o.message))
  end
  builder.setPositiveButton(o.positiveLabel or "确定", function()
    if o.onConfirm then o.onConfirm() end
  end)
  builder.setNegativeButton(o.negativeLabel or "取消", function()
    if o.onCancel then o.onCancel() end
  end)
  return show(builder)
end

-- 选择列表：用自定义列表视图实现，避免向 Java 传 CharSequence[]
-- opts.items = { {label=, value=}, ... }
function M.list(opts)
  local o = opts or {}
  local items = o.items or {}
  local colors = theme.colors()

  local container = kit.column({}, { width = "match", paddingTop = 4, paddingBottom = 8 })
  local dialog = nil

  for index, item in ipairs(items) do
    local isCancel = item.value == "cancel" or item.value == nil
    local row = kit.listItem({
      title = tostring(item.label or ""),
      titleColor = isCancel and colors.onSurfaceVariant or colors.onSurface,
      paddingVertical = 14,
      onClick = function()
        if dialog ~= nil then pcall(function() dialog.dismiss() end) end
        if o.onSelect then o.onSelect(item, index) end
      end,
    })
    container.addView(row)
  end

  dialog = MaterialAlertDialogBuilder(activity)
    .setTitle(tostring(o.title or "请选择"))
    .setView(container)
    .setNegativeButton(o.negativeLabel or "关闭", nil)
    .create()
  track(dialog)
  dialog.show()
  return dialog
end

-- 自定义内容对话框（传入 View）
function M.custom(opts)
  local o = opts or {}
  local builder = MaterialAlertDialogBuilder(activity)
    .setTitle(tostring(o.title or ""))
  if o.view ~= nil then builder.setView(o.view) end
  if o.positiveLabel then
    builder.setPositiveButton(o.positiveLabel, function(dialog, which)
      if o.onPositive then o.onPositive(dialog) end
    end)
  end
  if o.negativeLabel then
    builder.setNegativeButton(o.negativeLabel, function(dialog, which)
      if o.onNegative then o.onNegative(dialog) end
    end)
  end
  builder.setCancelable(o.cancelable ~= false)
  return show(builder)
end

-- 进度对话框（不可取消，用于登录等阻塞型操作）
function M.progress(message)
  local colors = theme.colors()
  local content = kit.row({
    kit.spinner(24),
    kit.column({
      kit.text(message or "请稍候…", {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurfaceVariant,
      }),
    }, { width = "0dp", weight = 1, marginStart = 16 }),
  }, { width = "match", padding = 24 })

  local dialog = MaterialAlertDialogBuilder(activity)
    .setView(content)
    .setCancelable(false)
    .create()
  track(dialog)
  dialog.show()
  return dialog
end

-- 轻提示：锚定在内容视图上，避免遮挡底部导航
function M.snackbar(message, actionLabel, onAction)
  local text = tostring(message or "")
  if text == "" then return nil end
  local ok, bar = pcall(function()
    local anchor = activity.findViewById(android.R.id.content)
    local snackbar = Snackbar.make(anchor, text, Snackbar.LENGTH_SHORT)
    if actionLabel ~= nil then
      snackbar.setAction(actionLabel, function(view)
        if onAction then onAction() end
      end)
    end
    snackbar.show()
    return snackbar
  end)
  if ok then return bar end
  return nil
end

function M.toast(message)
  pcall(function()
    local Toast = luajava.bindClass("android.widget.Toast")
    Toast.makeText(activity, tostring(message or ""), Toast.LENGTH_SHORT).show()
  end)
end

return M
