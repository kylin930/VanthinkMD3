-- Auth 迁移：二维码展示 + 状态轮询 + 接收端领取。
-- 协议（依据线上响应实测确认）：
--   生成端 GET https://zxzjurl.930390.xyz/create?auth=<token> -> { id, url }
--   状态   GET https://zxzjurl.930390.xyz/status/<code>       -> { used: bool }
--   接收端 GET <url>                                          -> { auth: <token> }
-- 二维码内容即返回的 url 本身，由纯 Lua 编码器生成，原生 Canvas 渲染。
-- 该服务为第三方中转：应用内明确提示风险，且仅在用户主动操作时调用。
-- 本版本不集成摄像头解码（运行时不提供 zxing / MLKit），接收端采用粘贴链接方式。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local state = require "app.state"
local transferService = require "app.services.transfer"
local authService = require "app.services.auth"
local qrcode = require "app.utils.qrcode"
local chart = require "app.ui.chart"

local M = {}

local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")

local POLL_INTERVAL_MS = 3000

-- 生成端：展示二维码并轮询扫描状态
function M.openSenderFlow()
  if not state.isLoggedIn() then
    dialogs.alert("未登录", "请先登录后再生成迁移二维码")
    return
  end

  local colors = theme.colors()
  local shell = kit.scrollPage({})
  local sub = router.subPage({ title = "Auth 迁移", content = shell.root })
  local page = { key = "transfer_sender", view = sub.root }

  local state_ = {
    code = nil,
    polling = true,
    timerJob = nil,
    statusText = "正在生成二维码…",
  }

  local qrHolder = kit.column({}, { width = "match", gravity = "center_horizontal" })
  local statusView = kit.text(state_.statusText, {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
    gravity = "center",
    width = "match",
  })

  local function stopPolling()
    state_.polling = false
    if state_.timerJob ~= nil then
      pcall(function() state_.timerJob.cancel() end)
      state_.timerJob = nil
    end
  end

  local function poll()
    if not state_.polling or state_.code == nil then return end
    transferService.checkStatus(state_.code, function(ok, data)
      if not state_.polling then return end
      if ok and data.used then
        state_.statusText = "二维码已被扫描领取"
        statusView.setText(state_.statusText)
        stopPolling()
        dialogs.alert("迁移完成", "另一台设备已经领取了登录状态。现在可以关闭本页面。")
        return
      end
      state_.statusText = "等待另一台设备扫描…"
      statusView.setText(state_.statusText)
    end)
  end

  local function render(created)
    shell.clear()
    shell.add(kit.spacer(8))
    shell.add(kit.card({
      kit.text("用另一台设备扫描此二维码", {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurface,
        bold = true,
        gravity = "center",
        width = "match",
      }),
      kit.spacer(12),
      (function()
        local matrix, err = qrcode.encode(created.url)
        if matrix == nil then
          return kit.stateView({
            icon = "warning",
            title = "二维码生成失败",
            message = tostring(err),
          })
        end
        return chart.qrCode(matrix, 240)
      end)(),
      kit.spacer(12),
      statusView,
      kit.spacer(6),
      kit.text(created.url, {
        size = 10,
        color = colors.outline,
        gravity = "center",
        width = "match",
        maxLines = 2,
      }),
    }, { marginHorizontal = 16, padding = 18 }))

    shell.add(kit.row({
      kit.button("刷新二维码", {
        style = "outlined",
        height = "42dp",
        size = kit.TYPOGRAPHY.label,
        onClick = function()
          stopPolling()
          page.start()
        end,
      }),
      kit.button("复制链接", {
        style = "text",
        height = "42dp",
        size = kit.TYPOGRAPHY.label,
        marginStart = 8,
        onClick = function()
          local ok = pcall(function()
            local ClipboardManager = luajava.bindClass("android.content.ClipboardManager")
            local ClipData = luajava.bindClass("android.content.ClipData")
            local manager = activity.getSystemService(activity.CLIPBOARD_SERVICE)
            manager.setPrimaryClip(ClipData.newPlainText("Vanthink Auth", created.url))
          end)
          dialogs.snackbar(ok and "链接已复制" or "复制失败")
        end,
      }),
    }, { width = "match", paddingStart = 16, paddingEnd = 16, gravity = "center" }))

    shell.add(kit.spacer(12))
    shell.add(kit.card({
      kit.row({
        kit.icon("warning", 20, colors.error),
        kit.text("安全提示", {
          size = kit.TYPOGRAPHY.label,
          color = colors.error,
          bold = true,
          marginStart = 10,
        }),
      }, { width = "match" }),
      kit.spacer(6),
      kit.text(
        "该二维码等价于你的登录凭据：任何拿到它的人都可以登录你的账号。"
        .. "请只在自己的设备上扫描，用完请立即关闭页面。链接由第三方服务生成，"
        .. "服务端会记录生成与领取行为。",
        { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant, width = "match" }),
    }, { marginHorizontal = 16, padding = 16 }))
    shell.add(kit.spacer(24))
  end

  function page.start()
    state_.polling = false
    shell.clear()
    shell.add(kit.row({
      kit.spinner(22),
      kit.text("正在生成二维码…", {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurfaceVariant,
        marginStart = 12,
      }),
    }, { width = "match", padding = 28, gravity = "center" }))

    transferService.create(function(ok, dataOrMessage)
      if not ok then
        shell.clear()
        shell.add(kit.stateView({
          icon = "cloud_off",
          title = "二维码生成失败",
          message = tostring(dataOrMessage),
          actionLabel = "重试",
          actionIcon = "refresh",
          onAction = function() page.start() end,
        }))
        return
      end
      state_.code = dataOrMessage.code
      state_.polling = true
      state_.statusText = "等待另一台设备扫描…"
      render(dataOrMessage)

      if state_.timerJob ~= nil then
        pcall(function() state_.timerJob.cancel() end)
      end
      state_.timerJob = activity.delay(POLL_INTERVAL_MS, function()
        poll()
        if state_.polling then
          state_.timerJob = activity.delay(POLL_INTERVAL_MS, function()
            poll()
          end)
        end
      end)
    end)
  end

  page.onShow = function() page.start() end
  page.onHide = function() stopPolling() end

  router.push(page)
  return page
end

-- 接收端：粘贴二维码链接领取 Token
-- onLoggedIn: 领取成功并保存后的回调
function M.openReceiveFlow(onLoggedIn)
  local colors = theme.colors()
  local content = kit.column({
    kit.text("把生成端二维码对应的链接粘贴到下方。", {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      width = "match",
    }),
    kit.spacer(6),
    kit.text("链接形如：https://zxzjurl.930390.xyz/xxxxxxxx", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      width = "match",
    }),
    kit.spacer(14),
  }, { width = "match", padding = 8 })

  local urlInput = kit.textInput({
    hint = "二维码链接",
    inputType = "text",
    singleLine = false,
    minLines = 2,
    maxLines = 4,
    textSize = 14,
  })
  content.addView(urlInput.root)
  content.addView(kit.spacer(12))
  content.addView(kit.button("从剪贴板粘贴", {
    style = "text",
    height = "40dp",
    size = kit.TYPOGRAPHY.label,
    onClick = function()
      local ok, text = pcall(function()
        local manager = activity.getSystemService(activity.CLIPBOARD_SERVICE)
        local clip = manager.getPrimaryClip()
        if clip == nil or clip.getItemCount() == 0 then return nil end
        return tostring(clip.getItemAt(0).coerceToText(activity))
      end)
      if ok and text ~= nil then
        urlInput.setText(text)
      else
        dialogs.snackbar("剪贴板为空或无法读取")
      end
    end,
  }))
  content.addView(kit.spacer(8))
  content.addView(kit.text(
    "本版本未集成摄像头二维码识别（运行时不提供可用解码库），"
    .. "所以采用粘贴链接的方式完成迁移。领取后旧链接立即失效。",
    { size = kit.TYPOGRAPHY.label, color = colors.outline, width = "match", maxLines = 5 }))

  dialogs.custom({
    title = "接收 Auth",
    view = content,
    positiveLabel = "领取",
    negativeLabel = "取消",
    onPositive = function(dialog)
      local url = urlInput.getText()
      if url == nil or url == "" then
        dialogs.snackbar("请先粘贴二维码链接")
        return
      end
      local progress = dialogs.progress("正在领取登录状态…")
      transferService.receive(url, function(ok, tokenOrMessage)
        dialogs.dismiss(progress)
        if not ok then
          dialogs.alert("领取失败", tostring(tokenOrMessage))
          return
        end
        pcall(function() dialog.dismiss() end)
        state.setToken(tokenOrMessage)
        authService.fetchAccount(function(accountOk)
          if not accountOk then
            dialogs.snackbar("登录状态已保存，但账号信息加载失败")
          end
          if onLoggedIn then onLoggedIn() end
        end)
      end)
    end,
  })
end

return M
