-- 登录页：独立设计的原生登录界面（MD3 输入框 + 加载态按钮 + 错误提示）。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local state = require "app.state"
local authService = require "app.services.auth"
local validator = require "app.utils.validator"
local logger = require "app.utils.logger"

local M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local TextInputLayout = luajava.bindClass("com.google.android.material.textfield.TextInputLayout")
local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
local MaterialStyle = luajava.bindClass("com.google.android.material.R$style")
local View = luajava.bindClass("android.view.View")

local REMEMBER_PHONE_KEY = "last_phone"

-- 登录成功 / 关闭登录页时回调
function M.create(opts)
  local o = opts or {}
  local colors = theme.colors()
  local page = { key = "login", passwordVisible = false }

  local scroll = kit.scrollPage({})
  page.view = scroll.root
  scroll.content.setPadding(theme.dp(24), 0, theme.dp(24), theme.dp(24))

  -- 品牌区
  local brand = kit.column({
    kit.row({
      kit.colorDot(52, colors.primaryContainer, colors.primary),
      kit.column({
        kit.text("Vanthink", {
          size = 22,
          color = colors.onSurface,
          bold = true,
        }),
        kit.text("在线助教 · 学生端", {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
        }),
      }, { width = "0dp", weight = 1, marginStart = 16 }),
    }, { width = "match" }),
    kit.spacer(24),
    kit.text("登录后查看作业与通知", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }),
  }, { width = "match", paddingTop = 56 })
  scroll.add(brand)
  scroll.add(kit.spacer(20))

  -- 输入区（kit.textInput：原生 EditText + 自绘 MD3 边框，不含 TextInputLayout 动画）
  local phoneInput = kit.textInput({
    hint = "手机号",
    inputType = "phone",
    textSize = 16,
  })
  local passwordInput = kit.textInput({
    hint = "密码",
    inputType = "password",
    textSize = 16,
    marginTop = 14,
  })

  -- 密码可见性切换（放在密码框右侧，避免使用 TextInputLayout 的 endIcon 动画）
  local passwordToggle = kit.iconButton("visibility_off", {
    size = 40,
    iconSize = 20,
    onClick = function()
      page.passwordVisible = not page.passwordVisible
      passwordInput.setPasswordVisible(page.passwordVisible)
      passwordToggle.setIcon(require("app.ui.icons").get(
        page.passwordVisible and "visibility" or "visibility_off", 20, colors.onSurfaceVariant))
    end,
  })
  passwordInput.holder.addView(passwordToggle)

  local errorView = kit.text("", {
    size = kit.TYPOGRAPHY.label,
    color = colors.error,
    maxLines = 3,
  })
  errorView.setVisibility(View.GONE)

  local loginButton = kit.button("登录", {
    width = "match",
    height = "52dp",
    marginTop = 20,
    onClick = function() end,
  })
  local progressRow = kit.row({
    kit.spinner(20),
    kit.text("正在登录…", {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      marginStart = 8,
    }),
  }, { width = "match", padding = 8, gravity = "center" })
  progressRow.setVisibility(View.GONE)

  local qrButton = kit.button("扫码登录 / 迁移 Auth", {
    width = "match",
    height = "48dp",
    style = "outlined",
    marginTop = 12,
    iconName = "qr_code",
    onClick = function()
      local transfer = require "app.ui.pages.transfer"
      transfer.openReceiveFlow(opts.onLoggedIn)
    end,
  })

  scroll.add(phoneInput.root)
  scroll.add(passwordInput.root)
  scroll.add(errorView)
  scroll.add(loginButton)
  scroll.add(progressRow)
  scroll.add(qrButton)
  scroll.add(kit.spacer(28))
  scroll.add(kit.text(
    "登录凭据仅保存在本机的系统 Keystore 加密存储中，不会明文落盘，也不会写入日志。",
    { size = kit.TYPOGRAPHY.label, color = colors.outline, maxLines = 4 }))

  -- 记住上次手机号（非敏感，便于再次登录）
  local remembered = require "app.storage.preferences".getString(REMEMBER_PHONE_KEY, nil)
  if remembered ~= nil then
    phoneInput.setText(remembered)
  end

  local function setLoading(loading)
    page.loading = loading
    loginButton.setEnabled(not loading)
    loginButton.setText(loading and "登录中…" or "登录")
    progressRow.setVisibility(loading and View.VISIBLE or View.GONE)
  end

  local function showError(message)
    errorView.setText(tostring(message or ""))
    errorView.setVisibility(View.VISIBLE)
  end

  local function clearError()
    errorView.setText("")
    errorView.setVisibility(View.GONE)
    phoneInput.clearError()
    passwordInput.clearError()
  end

  local function submit()
    if page.loading then return end
    local phone = phoneInput.getText()
    local password = passwordInput.getText()
    if not validator.isPhone(phone) then
      phoneInput.setError()
      showError("请输入正确的 11 位手机号")
      return
    end
    if password == nil or password == "" then
      passwordInput.setError()
      showError("请输入密码")
      return
    end
    clearError()
    setLoading(true)

    authService.login(phone, password, function(ok, message)
      setLoading(false)
      if not ok then
        showError(message)
        return
      end
      require "app.storage.preferences".setString(REMEMBER_PHONE_KEY, phone)
      logger.i("登录成功: " .. logger.maskPhone(phone))
      -- 登录成功后拉取账号信息，再进入主界面
      authService.fetchAccount(function(accountOk, accountOrMessage)
        if not accountOk then
          dialogs.snackbar("账号信息加载失败：" .. tostring(accountOrMessage))
        end
        if opts.onLoggedIn then opts.onLoggedIn() end
      end)
    end)
  end

  loginButton.setOnClickListener(function() submit() end)
  pcall(function()
    passwordInput.edit.setOnEditorActionListener(function(view, actionId, event)
      if actionId == 6 or actionId == 5 then
        submit()
        return true
      end
      return false
    end)
  end)

  page.showError = showError
  page.setLoading = setLoading
  -- 供外部按需聚焦（启动流程中不自动调用，避免输入法弹出导致重排）
  page.focusPhone = function()
    phoneInput.focus()
  end
  return page
end

-- 认证失效提示：由 Service 层的 44 错误码触发。
-- 通过 shell 集中处理，保证只提示一次并回到登录页。
function M.showAuthExpired()
  local shell = require "app.ui.shell"
  if shell.handleAuthInvalid then
    shell.handleAuthInvalid()
  end
end

return M
