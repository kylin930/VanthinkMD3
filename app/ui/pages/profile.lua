-- 我的：账号信息、Auth 迁移、主题设置、更新与关于、退出登录。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local state = require "app.state"
local config = require "app.config"
local authService = require "app.services.auth"
local updateService = require "app.services.update"
local logger = require "app.utils.logger"

local M = {}

local function accountAvatar(account, colors)
  local size = 60
  local headUrl = type(account) == "table" and account.head_url or nil
  if headUrl ~= nil and tostring(headUrl) ~= "" then
    local ImageView = luajava.bindClass("android.widget.ImageView")
    local GradientDrawable = luajava.bindClass("android.graphics.drawable.GradientDrawable")
    local view = loadlayout({
      ImageView,
      layout_width = size .. "dp",
      layout_height = size .. "dp",
      scaleType = "centerCrop",
    })
    local okClip = pcall(function()
      local drawable = GradientDrawable()
      drawable.setShape(GradientDrawable.OVAL)
      drawable.setColor(colors.surfaceContainerHighest)
      view.setBackground(drawable)
      view.setClipToOutline(true)
    end)
    if not okClip then view.setBackgroundColor(colors.surfaceContainerHighest) end
    pcall(function() activity.loadImage(headUrl, view) end)
    return view
  end
  return kit.colorDot(size, colors.primaryContainer, colors.primary)
end

function M.create()
  local colors = theme.colors()
  local page = {
    key = "profile",
    loadingAccount = false,
  }

  local shell = kit.scrollPage({
    onRefresh = function() page.refreshAccount() end,
  })
  page.view = shell.root

  function page.render()
    shell.clear()
    local account = state.account or {}
    local nickname = account.nickname or "未获取账号信息"
    local accountId = account.id

    shell.add(kit.pageHeader("我的", nil, {
      kit.iconButton("refresh", { onClick = function() page.refreshAccount() end }),
    }))
    shell.add(kit.spacer(4))

    -- 账号卡片
    shell.add(kit.card({
      kit.row({
        accountAvatar(account, colors),
        kit.column({
          kit.text(tostring(nickname), {
            size = kit.TYPOGRAPHY.headline,
            color = colors.onSurface,
            bold = true,
            maxLines = 1,
          }),
          kit.spacer(4),
          kit.text(accountId ~= nil and ("学生 ID：" .. tostring(accountId)) or "登录后展示账号信息", {
            size = kit.TYPOGRAPHY.label,
            color = colors.onSurfaceVariant,
          }),
          kit.spacer(6),
          kit.badge(state.isLoggedIn() and "已登录" or "未登录", {
            background = state.isLoggedIn() and colors.tertiaryContainer
              or colors.surfaceContainerHighest,
            color = state.isLoggedIn() and colors.onTertiaryContainer or colors.onSurfaceVariant,
          }),
        }, { width = "0dp", weight = 1, marginStart = 16 }),
      }, { width = "match" }),
    }, { marginHorizontal = 16, padding = 18 }))

    -- 账号
    shell.add(kit.sectionTitle("账号"))
    shell.add(kit.group({
      kit.listItem({
        icon = "qr_code",
        title = "Auth 迁移",
        subtitle = "生成一次性二维码，把登录状态迁移到其他设备",
        showChevron = true,
        onClick = function()
          local transfer = require "app.ui.pages.transfer"
          transfer.openSenderFlow()
        end,
      }),
      kit.listItem({
        icon = "lock",
        title = "登录凭据",
        subtitle = "Token 保存在系统 Keystore 加密存储中",
        onClick = function()
          local security = require "app.ui.pages.security"
          router.push(security.create())
        end,
        showChevron = true,
      }),
    }))

    -- 外观
    shell.add(kit.sectionTitle("外观"))
    shell.add(kit.group({
      kit.listItem({
        icon = "palette",
        title = "主题设置",
        subtitle = theme.summary(),
        showChevron = true,
        onClick = function()
          local themePage = require "app.ui.pages.theme_settings"
          router.push(themePage.create())
        end,
      }),
    }))

    -- 关于
    shell.add(kit.sectionTitle("关于"))
    shell.add(kit.group({
      kit.listItem({
        icon = "update",
        title = "检查更新",
        subtitle = "获取最新版本说明（也需要网络可用）",
        onClick = function() page.checkUpdate() end,
      }),
      kit.listItem({
        icon = "history",
        title = "更新日志",
        subtitle = "查看最近一次拉取到的版本说明",
        onClick = function()
          local changelog = require "app.ui.pages.changelog"
          router.push(changelog.create(true))
        end,
        showChevron = true,
      }),
      kit.listItem({
        icon = "info",
        title = "关于 VanthinkMD3",
        subtitle = string.format("版本 %s · NeLuaJ+ 原生应用", config.APP_VERSION),
        showChevron = true,
        onClick = function()
          local about = require "app.ui.pages.about"
          router.push(about.create())
        end,
      }),
      kit.listItem({
        icon = "warning",
        title = "隐私与安全说明",
        subtitle = "数据流向、凭据存储与第三方服务说明",
        showChevron = true,
        onClick = function()
          local security = require "app.ui.pages.security"
          router.push(security.create())
        end,
      }),
    }))

    -- 退出登录
    shell.add(kit.spacer(16))
    shell.add(kit.row({
      kit.button("退出登录", {
        width = "match",
        height = "48dp",
        style = "outlined",
        onClick = function() page.logout() end,
      }),
    }, { width = "match", paddingStart = 16, paddingEnd = 16 }))
    shell.add(kit.spacer(28))
  end

  function page.refreshAccount()
    if page.loadingAccount then return end
    page.loadingAccount = true
    authService.fetchAccount(function(ok, message)
      page.loadingAccount = false
      shell.setRefreshing(false)
      if not ok then
        dialogs.snackbar("账号信息刷新失败：" .. tostring(message))
      end
      page.render()
    end)
  end

  function page.checkUpdate()
    dialogs.snackbar("正在检查更新…")
    updateService.fetch(function(ok, dataOrMessage)
      if not ok then
        dialogs.alert("检查更新失败", tostring(dataOrMessage))
        return
      end
      if updateService.isNewVersion(dataOrMessage.version) then
        updateService.ackVersion(dataOrMessage.version)
        local changelog = require "app.ui.pages.changelog"
        changelog.showDialog(dataOrMessage, false)
      else
        dialogs.alert("已是最新版本", string.format("当前服务端版本：%s", tostring(dataOrMessage.version)))
      end
    end)
  end

  function page.logout()
    dialogs.confirm({
      title = "退出登录",
      message = "退出后将清除本机保存的登录凭据，需要重新输入手机号与密码。",
      positiveLabel = "退出登录",
      negativeLabel = "取消",
      onConfirm = function()
        authService.logout()
        logger.i("用户主动退出登录")
        local shellModule = require "app.ui.shell"
        shellModule.showLogin()
      end,
    })
  end

  function page.onShow()
    -- 页面实例被路由缓存复用；账号信息未变化时不要整页重建，否则切 tab 会闪烁。
    -- 账号为空时才请求刷新，refreshAccount 拿到结果后再渲染一次。
    if state.account == nil and state.isLoggedIn() then
      page.refreshAccount()
    end
  end

  page.render()
  return page
end

return M
