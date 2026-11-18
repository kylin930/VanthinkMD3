-- 应用外壳：登录页与主界面（底部导航 + 内容容器）之间的切换、系统 Insets、返回键。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local router = require "app.router"
local state = require "app.state"
local logger = require "app.utils.logger"
local updateService = require "app.services.update"
local dialogs = require "app.ui.dialogs"

local M = {}

local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
local BottomNavigationView = luajava.bindClass("com.google.android.material.bottomnavigation.BottomNavigationView")
local View = luajava.bindClass("android.view.View")
local ViewCompat = luajava.bindClass("androidx.core.view.ViewCompat")
local WindowInsetsCompat = luajava.bindClass("androidx.core.view.WindowInsetsCompat")

M.root = nil
M.container = nil
M.bottomNav = nil
M.mode = nil
M.backCallbackAdded = false
M.authInvalidHandling = false

local TAB_ITEMS = {
  { key = "homework", label = "作业", icon = "assignment" },
  { key = "notifications", label = "通知", icon = "notifications" },
  { key = "statistics", label = "统计", icon = "insights" },
  { key = "profile", label = "我的", icon = "person" },
}

local TAB_IDS = {}

local function buildBottomNav(colors)
  -- 底部导航：宽度占满、高度自适应。用 BottomNavigationView 自身的
  -- generateDefaultLayoutParams 会得到 FrameLayout.LayoutParams（缺少 weight），
  -- 因此显式给 LinearLayout.LayoutParams，保证它和内容容器的 weight 配合正确。
  local nav = BottomNavigationView(activity)
  kit.applyLinearParams(nav, { width = "match", height = "wrap" })
  pcall(function()
    nav.setBackgroundColor(theme.normalize(colors.surfaceContainer))
    nav.setLabelVisibilityMode(1)
  end)

  local menu = nav.getMenu()
  menu.clear()
  for index, item in ipairs(TAB_ITEMS) do
    local menuItem = menu.add(0, index, index - 1, item.label)
    TAB_IDS[index] = item.key
    pcall(function()
      local drawable = require "app.ui.icons".get(item.icon, 22, colors.onSurfaceVariant)
      if drawable ~= nil then menuItem.setIcon(drawable) end
    end)
  end

  nav.setOnItemSelectedListener(function(item)
    local index = item.getItemId()
    local key = TAB_IDS[index]
    if key == nil then return false end
    if M.mode ~= "main" then return true end
    router.showTab(key)
    return true
  end)

  return nav
end

-- 系统栏适配说明：
-- 本应用使用普通的 NoActionBar 主题，系统默认会把内容视图放在状态栏与导航栏之间
-- （decorFitsSystemWindows 默认 true），因此**不需要**手动加 padding。
-- 早期版本在 ViewCompat.setOnApplyWindowInsetsListener 里调用 view.setPadding：
-- 修改 padding 会触发重新布局 → 再次分发 Insets → 再次 setPadding，
-- 形成布局循环，表现为整屏持续闪烁。这里改为不做任何 Insets 改写。
local function applyInsets(root)
  -- 保留函数以便将来切换 edge-to-edge 模式时集中处理；
  -- 若改为 WindowCompat.setDecorFitsSystemWindows(window, false)，
  -- 必须在这里用「值未变化则直接返回 / 并消费 insets」的幂等写法，避免布局循环。
  return root
end

function M.init()
  local colors = theme.colors()
  -- 先给窗口铺一个与主题一致的底色。
  -- 否则首帧会先显示主题默认的背景色再被内容覆盖，视觉上就是一次闪白。
  pcall(function()
    local ColorDrawable = luajava.bindClass("android.graphics.drawable.ColorDrawable")
    activity.getWindow().setBackgroundDrawable(ColorDrawable(theme.normalize(colors.surface)))
  end)
  local root = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = colors.surface,
  })
  M.root = root
  activity.setContentView(root)
  applyInsets(root)

  -- 返回键：优先处理二级页面返回（只注册一次，避免重复回调）
  if M.backCallbackAdded then return end
  M.backCallbackAdded = true
  pcall(function()
    activity.addOnBackPressedCallback(function()
      if M.mode == "main" and router.canGoBack() then
        router.back()
        return
      end
      if M.mode == "main" and router.currentKey ~= "homework" then
        router.showTab("homework")
        if M.bottomNav ~= nil then
          M.bottomNav.setSelectedItemId(1)
        end
        return
      end
      activity.finish()
    end)
  end)
end

-- 认证失效：只提示一次，然后回到登录页
function M.handleAuthInvalid()
  if M.authInvalidHandling then return end
  M.authInvalidHandling = true
  logger.w("登录状态已失效，返回登录页")
  local stateModule = state
  stateModule.reset()
  require("app.services.http").resetAuthHandled()
  pcall(function()
    dialogs.dismissAll()
  end)
  M.showLogin()
  dialogs.alert("登录状态已失效", "服务器返回验证失败，请重新登录。")
  M.authInvalidHandling = false
end

local function clearRoot()
  if M.root ~= nil then
    pcall(function() M.root.removeAllViews() end)
  end
  router.init(nil)
  M.container = nil
  M.bottomNav = nil
end

-- 主界面
function M.showMain()
  local colors = theme.colors()
  clearRoot()
  M.mode = "main"

  -- 内容容器必须占满「除底部导航以外的全部高度」。
  -- 注意：独立 loadlayout 出来的 FrameLayout 根视图，其 LayoutParams 由控件自身决定
  -- （FrameLayout.LayoutParams），其中**没有 weight 字段**。
  -- 之前直接写 layout_height="0dp" + layout_weight=1，weight 被丢弃，
  -- 结果容器高度恒为 0：界面只剩底部导航栏，内容区完全不可见，
  -- 且 ScrollView 在 0 高容器内反复测量重绘，表现为持续闪烁。
  -- 因此这里显式设置为 LinearLayout.LayoutParams(MATCH_PARENT, 0) 并赋予 weight=1。
  local container = loadlayout({
    FrameLayout,
    layout_width = "match",
    layout_height = "wrap",
    BackgroundColor = colors.surface,
  })
  kit.applyLinearParams(container, {
    width = "match",
    height = "0dp",
    weight = 1,
  })

  local nav = buildBottomNav(colors)

  M.container = container
  M.bottomNav = nav

  router.init(container)
  router.registerTab("homework", function()
    return require "app.ui.pages.homework".create()
  end)
  router.registerTab("notifications", function()
    return require "app.ui.pages.notifications".create()
  end)
  router.registerTab("statistics", function()
    return require "app.ui.pages.statistics".create()
  end)
  router.registerTab("profile", function()
    return require "app.ui.pages.profile".create()
  end)

  -- 顺序很重要：LinearLayout 的 weight 只作用于声明了 weight 的子视图，
  -- 底部导航保持 wrap_content，内容区吃掉剩余高度。
  M.root.addView(container)
  M.root.addView(nav)

  router.showTab("homework")
  nav.setSelectedItemId(1)
  M.checkUpdateSilently()
end

-- 登录界面
function M.showLogin()
  clearRoot()
  M.mode = "login"
  local loginPage = require "app.ui.pages.login".create({
    onLoggedIn = function()
      M.showMain()
    end,
  })
  -- 登录页作为唯一子视图占满整屏（同样需要显式 LayoutParams）
  kit.applyLinearParams(loginPage.view, {
    width = "match",
    height = "match",
  })
  M.root.addView(loginPage.view)
  -- 不自动聚焦输入框：弹出输入法会引起窗口重新布局，
  -- 在部分机型上表现为进入页面时的一次明显闪烁。
end

-- 启动：根据是否有 Token 决定首屏
function M.start()
  state.bootstrap()
  if state.isLoggedIn() then
    M.showMain()
    -- 后台校验登录态；失效时统一走 handleAuthInvalid（只提示一次）
    require "app.services.auth".fetchAccount(function(ok, message, result)
      if ok then return end
      if result ~= nil and (result.kind == "auth" or result.errcode == 44) then
        M.handleAuthInvalid()
      end
    end)
  else
    M.showLogin()
  end
end

-- 静默检查更新：失败不打扰用户
function M.checkUpdateSilently()
  updateService.fetch(function(ok, dataOrMessage)
    if not ok then
      logger.d("更新检查失败（忽略）: " .. tostring(dataOrMessage))
      return
    end
    if updateService.isNewVersion(dataOrMessage.version) then
      updateService.ackVersion(dataOrMessage.version)
      local changelog = require "app.ui.pages.changelog"
      changelog.showDialog(dataOrMessage, false)
    end
  end)
end

return M
