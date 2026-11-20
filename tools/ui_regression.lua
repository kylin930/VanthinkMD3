-- UI 回归诊断（开发期工具，不参与运行，不随打包产物发布）
--
-- 与早期 diag_* 脚本的区别：
--   * 不再用 pcall(create) 判断“页面正常”——创建成功只说明没有抛异常；
--   * 这里真实创建 View、真实测量（measure/layout）后读取 getMeasuredWidth/Height，
--     检查二级页正文是否挂载、列表项标题与副标题是否有宽度、统计页卡片是否被压成零宽；
--   * 服务层全部用固定桩数据替换，不访问网络，结果可复现；
--   * 需要布局完成的检查刻意放在「下一步」执行（每步之间等待一帧以上），
--     避免读到首帧之前恒为 0 的测量值。
--
-- 用法：在 NeLuaJ+ 中直接运行本文件（不要作为工程入口）。
-- 输出：_ui_regression.txt（逐项 PASS/FAIL），终端只打印摘要。

local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_ui_regression.txt"

local lines = {}
local passCount, failCount = 0, 0
local rawPrint = print

local function log(text) lines[#lines + 1] = tostring(text or "") end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

-- 页面与组件内部会 print 日志，统一收进报告，避免刷终端
print = function(...)
  local parts = {}
  for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
  log("      LOG " .. table.concat(parts, " "):gsub("\n", " "):sub(1, 300))
end

local function pass(label, detail)
  passCount = passCount + 1
  log(string.format("PASS  %s%s", label, detail and ("  [" .. tostring(detail) .. "]") or ""))
  flush()
end

local function fail(label, detail)
  failCount = failCount + 1
  log(string.format("FAIL  %s%s", label, detail and ("  [" .. tostring(detail) .. "]") or ""))
  flush()
end

local function check(label, ok, detail)
  if ok then pass(label, detail) else fail(label, detail) end
  return ok and true or false
end

-- ===== 基础模块（必须先于视图工具声明：工具函数依赖它们） =====

local theme = require "app.ui.theme"
local kit = require "app.ui.kit"
local state = require "app.state"
local router = require "app.router"

local dp = theme.dp
local colors = theme.colors()
local WAIT_MS = 450
local screenWidth = activity.getResources().getDisplayMetrics().widthPixels

-- ===== 视图工具 =====

local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
local MeasureSpec = luajava.bindClass("android.view.View$MeasureSpec")

local function childCount(view)
  local ok, count = pcall(function() return view.getChildCount() end)
  if ok and type(count) == "number" then return count end
  return 0
end

local function childAt(view, index)
  local ok, child = pcall(function() return view.getChildAt(index) end)
  if ok then return child end
  return nil
end

local function walk(view, fn, depth)
  depth = depth or 0
  if view == nil or depth > 48 then return end
  fn(view, depth)
  local count = childCount(view)
  for index = 0, count - 1 do
    walk(childAt(view, index), fn, depth + 1)
  end
end

local function classOf(view)
  local name = ""
  pcall(function() name = tostring(view.getClass().getName()) end)
  return name
end

local function widthOf(view) return view and view.getMeasuredWidth() or 0 end
local function heightOf(view) return view and view.getMeasuredHeight() or 0 end

local function collectTexts(root)
  local list = {}
  walk(root, function(view, depth)
    local ok, value = pcall(function() return view.getText() end)
    if ok and value ~= nil then
      local text = tostring(value)
      if text ~= "" then
        list[#list + 1] = {
          text = text,
          width = view.getMeasuredWidth(),
          height = view.getMeasuredHeight(),
          depth = depth,
          view = view,
        }
      end
    end
  end)
  return list
end

local function findText(root, needle)
  for _, item in ipairs(collectTexts(root)) do
    if string.find(item.text, needle, 1, true) ~= nil then return item end
  end
  return nil
end

local function findViewsByClass(root, needle)
  local found = {}
  walk(root, function(view)
    if string.find(classOf(view), needle, 1, true) ~= nil then found[#found + 1] = view end
  end)
  return found
end

local function parentOf(view)
  local ok, parent = pcall(function() return view.getParent() end)
  if ok then return parent end
  return nil
end

-- 按类名收集，并可选地按文本过滤（textNeedle = nil 表示只收文本为空的按钮）
local function buttonsMatching(root, classNeedle, textNeedle)
  local list = {}
  for _, view in ipairs(findViewsByClass(root, classNeedle)) do
    local ok, value = pcall(function() return view.getText() end)
    local text = (ok and value ~= nil) and tostring(value) or nil
    if textNeedle == nil then
      if text == nil or text == "" then list[#list + 1] = view end
    elseif text ~= nil and string.find(text, textNeedle, 1, true) ~= nil then
      list[#list + 1] = view
    end
  end
  return list
end

-- 位图身份：icons.get 按 name|size|color 缓存同一个 drawable，
-- 用 Bitmap 的 identityHashCode 就能判断「当前菜单图标用的是哪一套」。
local function bitmapId(drawable)
  if drawable == nil then return nil end
  local ok, bitmap = pcall(function() return drawable.getBitmap() end)
  if not ok or bitmap == nil then return nil end
  local okId, id = pcall(function()
    return luajava.bindClass("java.lang.System").identityHashCode(bitmap)
  end)
  if okId then return id end
  return nil
end

local function findCardContaining(root, needle)
  for _, card in ipairs(findViewsByClass(root, "MaterialCardView")) do
    if findText(card, needle) ~= nil then return card end
  end
  return nil
end

local function clickableAncestor(view)
  local current = view
  for _ = 1, 14 do
    if current == nil then return nil end
    local ok, clickable = pcall(function()
      return current.isClickable() and current.hasOnClickListeners()
    end)
    if ok and clickable == true then return current end
    local okParent, parent = pcall(function() return current.getParent() end)
    if not okParent then return nil end
    current = parent
  end
  return nil
end

-- 在一个固定宽度的宿主里真实测量（模拟 320dp 窄屏、放大字体等场景）
local function measureAt(view, widthPx, heightMode)
  local host = FrameLayout(activity)
  local ok = pcall(function() host.addView(view) end)
  if not ok then return nil end
  local widthSpec = MeasureSpec.makeMeasureSpec(widthPx, MeasureSpec.EXACTLY)
  local heightSpec
  if heightMode == "at_most" then
    heightSpec = MeasureSpec.makeMeasureSpec(theme.dp(2400), MeasureSpec.AT_MOST)
  else
    heightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
  end
  pcall(function()
    host.measure(widthSpec, heightSpec)
    host.layout(0, 0, host.getMeasuredWidth(), host.getMeasuredHeight())
  end)
  return host
end

-- 二级页结构固定为 [返回栏][内容容器]，内容容器的子视图就是页面正文
local function subMeta(pageView)
  local bar = childAt(pageView, 0)
  local holder = childAt(pageView, 1)
  local first = holder and childAt(holder, 0) or nil
  return {
    bar = bar,
    holder = holder,
    count = holder and childCount(holder) or -1,
    first = first,
    holderWidth = widthOf(holder),
    holderHeight = heightOf(holder),
    firstWidth = widthOf(first),
    firstHeight = heightOf(first),
  }
end

local function checkSubPage(tag, pageView, expectKey)
  local router = require "app.router"
  check(tag .. "：路由已切换", router.current ~= nil
    and (expectKey == nil or router.current.key == expectKey),
    tostring(router.current and router.current.key))
  local meta = subMeta(pageView)
  check(tag .. "：内容容器恰好挂载 1 个正文视图", meta.count == 1,
    "childCount=" .. tostring(meta.count))
  check(tag .. "：正文宽度 > 0", meta.firstWidth > 0, meta.firstWidth .. "px")
  check(tag .. "：正文高度 > 0", meta.firstHeight > 0, meta.firstHeight .. "px")
  check(tag .. "：内容区高度 > 0", meta.holderHeight > 0, meta.holderHeight .. "px")
  check(tag .. "：正文宽度铺满内容区",
    meta.holderWidth > 0 and math.abs(meta.firstWidth - meta.holderWidth) <= dp(2),
    string.format("%d / %d", meta.firstWidth, meta.holderWidth))
  check(tag .. "：返回栏存在", meta.bar ~= nil and childCount(meta.bar) >= 2,
    "bar children=" .. tostring(meta.bar and childCount(meta.bar) or -1))
  return meta
end

-- ===== 环境准备 =====

-- 桩数据：在 require 之后覆盖服务函数，保证不发起任何网络请求
local function installStubs()
  local homeworkService = require "app.services.homework"
  homeworkService.fetchList = function(opts, callback)
    local list = {}
    for index = 1, 4 do
      list[index] = {
        id = 1000 + index,
        name = "回归作业 " .. index,
        vanclass_name = "高一(3)班",
        type = { name = "普通模式" },
        testbank_count = 12,
        completion_rate = index * 20,
        created_at = "2026/08/0" .. index,
        description = "固定桩数据",
      }
    end
    callback(true, { list = list, total = 4, page = 1, hasMore = false })
  end
  homeworkService.fetchDetail = function(id, callback)
    callback(true, {
      name = "回归测试作业",
      teacher_name = "王老师",
      vanclass = { name = "高一(3)班" },
      type = { name = "普通模式" },
      created_at = "2026/08/01",
      testbanks = {
        { id = 1, name = "练习项一", game = { id = 11, name = "单词消消乐" }, standard = 0.8, accuracy = 90 },
        { id = 2, name = "练习项二", game = { id = 12, name = "听力填空" }, standard = 0.8, accuracy = 85 },
        { id = 3, name = "练习项三", game = { id = 13, name = "语音跟读" }, is_voice = 1 },
      },
    })
  end

  local noticeService = require "app.services.notice"
  noticeService.fetchList = function(opts, callback)
    local list = {}
    for index = 1, 3 do
      list[index] = {
        id = 2000 + index,
        content = "回归测试通知内容 " .. index .. "：这是一段用于验证正文换行的较长文本。",
        created_at = "2026/08/0" .. index,
        has_read = index - 1,
        sender = { nickname = "张老师" },
      }
    end
    callback(true, { list = list, count = 3, page = 1, hasMore = false })
  end
  noticeService.markRead = function(ids, callback)
    if callback then callback(true) end
    return nil
  end

  local statisticsService = require "app.services.statistics"
  statisticsService.fetchReport = function(opts, callback)
    local daily = {}
    for day = 1, 20 do
      daily[day] = { day = string.format("2026/08/%02d", day), score = day * 7, time = day * 3 }
    end
    callback(true, {
      practice = { count = 128, avg = 12.5, monthAvg = 9 },
      exercise = { count = 1024, avg = 96.4, monthAvg = 88 },
      days = { count = 21, avg = 32.5, monthAvg = 28 },
      photo = { count = 7, avg = 1.2, monthAvg = 1 },
      pl = { startTime = "2026/01/05 08:00:00", totalTime = 1520, avgTime = 46 },
      daily = daily,
    })
  end

  local authService = require "app.services.auth"
  authService.fetchAccount = function(callback) callback(true) end
  authService.logout = function() end

  local updateService = require "app.services.update"
  updateService.fetch = function(callback)
    callback(true, {
      version = "9.9.9",
      updateTime = "2026-08-01",
      added = { "新增回归测试项", "新增 UI 尺寸断言" },
      improved = { "优化统计页双列卡片宽度分配" },
      fixed = { "修复二级页面正文未挂载", "修复列表项标题宽度为 0" },
      note = "本条为回归诊断使用的桩数据。",
    })
  end
  updateService.isNewVersion = function() return false end

  local transferService = require "app.services.transfer"
  transferService.create = function(callback)
    callback(false, "诊断模式：不访问第三方服务")
    return nil
  end
end

pcall(function() theme.bootstrap() end)
installStubs()
local shell = require "app.ui.shell"
shell.handleAuthInvalid = function() end
pcall(function() state.setToken("ui_regression_fake_token") end)
pcall(function() state.setAccount({ id = 12345, nickname = "回归测试同学" }) end)

-- ===== 步骤队列 =====

local queue = {}
local function step(name, fn) queue[#queue + 1] = { name = name, fn = fn } end
local cursor = 0

local function finish()
  log("")
  log(string.format("=== 汇总：PASS %d / FAIL %d ===", passCount, failCount))
  if failCount == 0 then
    log("结论：全部 UI 结构断言通过")
  else
    log("结论：存在失败项，需要修复后再验收")
  end
  flush()
  pcall(function() state.clearToken() end)
  print = rawPrint
  rawPrint(string.format("ui_regression done: PASS %d FAIL %d -> %s", passCount, failCount, OUT))
end

local function runNext()
  cursor = cursor + 1
  local item = queue[cursor]
  if item == nil then finish() return end
  log("")
  log("=== " .. item.name)
  flush()
  local ok, err = pcall(item.fn)
  if not ok then
    fail(item.name .. " 执行异常", tostring(err):gsub("\n", " "):sub(1, 300))
  end
  flush()
  activity.delay(WAIT_MS, runNext)
end

-- ===== 一、主界面 / 作业列表 / 作业详情 =====

step("初始化外壳并显示主界面", function()
  log(string.format("屏幕：%dpx 宽（%ddp），当前主题模式 %s",
    screenWidth, kit.windowWidthDp(), tostring(theme.mode())))
  pcall(function() shell.init() end)
  pcall(function() shell.showMain() end)
  check("外壳根视图已创建", shell.root ~= nil)
end)

step("作业列表渲染与卡片点击", function()
  check("内容容器只挂 1 个页面视图",
    router.container ~= nil and childCount(router.container) == 1,
    "childCount=" .. tostring(router.container and childCount(router.container) or -1))
  local summary = findText(router.current.view, "共 4 个作业")
  check("作业列表摘要可见", summary ~= nil and summary.width > 0,
    summary and (summary.width .. "px") or "未找到")

  local cards = findViewsByClass(router.current.view, "MaterialCardView")
  local target = nil
  for _, card in ipairs(cards) do
    if clickableAncestor(card) ~= nil then target = card break end
  end
  check("找到可点击的作业卡片", target ~= nil, "卡片数=" .. #cards)
  if target ~= nil then pcall(function() target.performClick() end) end
end)

step("作业详情页正文挂载", function()
  local page = router.current
  check("已进入作业详情", page ~= nil and page.key == "homework_detail",
    tostring(page and page.key))
  if page == nil then return end
  local meta = checkSubPage("作业详情", page.view, "homework_detail")
  local practiceTitle = findText(page.view, "练习列表")
  check("详情正文文字可见", practiceTitle ~= nil and practiceTitle.width > 0,
    practiceTitle and (practiceTitle.width .. "px") or "未找到")
  local badge = findText(page.view, "达标")
  check("达标徽标可见", badge ~= nil and badge.width > 0,
    badge and (badge.width .. "px") or "未找到")
  local scroll = findViewsByClass(page.view, "NestedScrollView")[1]
  check("正文滚动容器存在", scroll ~= nil)
  if scroll ~= nil then
    local contentHeight = heightOf(childAt(scroll, 0))
    local viewportHeight = scroll.getMeasuredHeight()
    if contentHeight > viewportHeight + dp(8) then
      local before = scroll.getScrollY()
      pcall(function() scroll.scrollTo(0, dp(160)) end)
      check("正文可以上下滚动", scroll.getScrollY() > before,
        string.format("%d -> %d", before, scroll.getScrollY()))
    else
      pass("正文内容未超出视口，无需滚动", string.format("%d ≤ %d", contentHeight, viewportHeight))
    end
  end
  log(string.format("      内容区 %dx%d，正文 %dx%d",
    meta.holderWidth, meta.holderHeight, meta.firstWidth, meta.firstHeight))
  router.back()
end)

step("返回作业列表（视图复用）", function()
  check("已返回作业 tab", router.currentKey == "homework", tostring(router.currentKey))
  check("容器内仍只有一个页面视图", childCount(router.container) == 1,
    "childCount=" .. childCount(router.container))
  local title = findText(router.current.view, "回归作业 1")
  check("返回后列表内容仍可见", title ~= nil and title.width > 0,
    title and (title.width .. "px") or "未找到")
end)

-- ===== 二、通知列表 / 通知详情 =====

step("打开通知列表", function()
  router.showTab("notifications")
  check("通知 tab 已显示", router.currentKey == "notifications", tostring(router.currentKey))
end)

step("通知列表渲染并进入详情", function()
  local header = findText(router.current.view, "通知")
  check("页头标题可见", header ~= nil and header.width > 0,
    header and (header.width .. "px") or "未找到")
  local cards = findViewsByClass(router.current.view, "MaterialCardView")
  check("通知卡片已渲染", #cards > 0, "卡片数=" .. #cards)
  if #cards > 0 then pcall(function() cards[1].performClick() end) end
end)

step("通知详情页正文挂载", function()
  local page = router.current
  check("已进入通知详情", page ~= nil and page.key == "notice_detail",
    tostring(page and page.key))
  if page == nil then return end
  checkSubPage("通知详情", page.view, "notice_detail")
  local body = findText(page.view, "回归测试通知内容 1")
  check("通知正文可见", body ~= nil and body.width > 0,
    body and (body.width .. "px") or "未找到")
  router.back()
end)

-- ===== 三、二级页：主题设置 / 关于 / 隐私与安全（含多层返回） =====

step("进入主题设置页", function()
  router.push(require("app.ui.pages.theme_settings").create())
end)

step("主题设置页正文挂载", function()
  local page = router.current
  check("已进入主题设置", page ~= nil and page.key == "theme_settings",
    tostring(page and page.key))
  if page == nil then return end
  checkSubPage("主题设置", page.view, "theme_settings")
  local section = findText(page.view, "深色模式")
  check("分组标题可见", section ~= nil and section.width > 0,
    section and (section.width .. "px") or "未找到")
  local preset = findText(page.view, "赤陶红")
  check("预设主题色文字可见", preset ~= nil and preset.width > 0,
    preset and (preset.width .. "px") or "未找到")
  local note = findText(page.view, "注意：Android 12")
  check("提示卡片正文可见", note ~= nil and note.width > 0,
    note and (note.width .. "px") or "未找到")
  router.push(require("app.ui.pages.about").create())
end)

step("关于页正文挂载（第二层）", function()
  local page = router.current
  check("已进入关于页", page ~= nil and page.key == "about", tostring(page and page.key))
  if page == nil then return end
  local meta = checkSubPage("关于", page.view, "about")
  if meta.first ~= nil then
    local version = findText(meta.first, "版本")
    check("关于页版本文字可见", version ~= nil and version.width > 0,
      version and (version.width .. "px") or "未找到")
  end
  router.push(require("app.ui.pages.security").create())
end)

step("隐私与安全页正文挂载（第三层）", function()
  local page = router.current
  check("已进入隐私与安全页", page ~= nil and page.key == "security",
    tostring(page and page.key))
  if page == nil then return end
  local meta = checkSubPage("隐私与安全", page.view, "security")
  if meta.first ~= nil then
    local block = findText(meta.first, "登录凭据")
    check("安全说明正文可见", block ~= nil and block.width > 0,
      block and (block.width .. "px") or "未找到")
  end
  router.back()
end)

step("多层返回：关于 → 主题设置 → 作业", function()
  check("已返回关于页", router.currentKey == "about", tostring(router.currentKey))
  local aboutFirst = subMeta(router.current.view).first
  check("关于页正文仍有宽度", widthOf(aboutFirst) > 0, widthOf(aboutFirst) .. "px")
  router.back()
  check("已返回主题设置页", router.currentKey == "theme_settings", tostring(router.currentKey))
  router.back()
  -- 入栈前的 tab 是通知（见“打开通知列表”），返回后应回到通知而不是作业
  check("已回到入栈前的通知 tab", router.currentKey == "notifications",
    tostring(router.currentKey))
  check("容器内只有一个页面视图", childCount(router.container) == 1,
    "childCount=" .. childCount(router.container))
end)

step("进入更新日志页", function()
  router.push(require("app.ui.pages.changelog").create(true))
end)

step("更新日志页正文挂载", function()
  local page = router.current
  check("已进入更新日志", page ~= nil and page.key == "changelog", tostring(page and page.key))
  if page == nil then return end
  local meta = checkSubPage("更新日志", page.view, "changelog")
  if meta.first ~= nil then
    local item = findText(meta.first, "新增回归测试项")
    check("长文本条目换行后仍有宽度", item ~= nil and item.width > 0,
      item and (item.width .. "px") or "未找到")
  end
  router.back()
end)

step("进入 Auth 迁移页", function()
  require("app.ui.pages.transfer").openSenderFlow()
end)

step("Auth 迁移页正文挂载", function()
  local page = router.current
  check("已进入 Auth 迁移页", page ~= nil and page.key == "transfer_sender",
    tostring(page and page.key))
  if page == nil then return end
  local meta = subMeta(page.view)
  check("正文已挂载（1 个子视图）", meta.count == 1, "childCount=" .. tostring(meta.count))
  check("正文宽度 > 0", meta.firstWidth > 0, meta.firstWidth .. "px")
  local failure = findText(page.view, "二维码生成失败")
  check("失败态正文可见（桩数据故意返回失败）", failure ~= nil and failure.width > 0,
    failure and (failure.width .. "px") or "未找到")
  router.back()
end)

-- ===== 四、我的页面 =====

local PROFILE_ITEMS = {
  { title = "Auth 迁移", subtitle = "生成一次性二维码" },
  { title = "登录凭据", subtitle = "Token 保存在系统 Keystore" },
  { title = "主题设置", subtitle = nil },
  { title = "检查更新", subtitle = "获取最新版本说明" },
  { title = "更新日志", subtitle = "查看最近一次拉取到的版本说明" },
  { title = "关于 VanthinkMD3", subtitle = "版本" },
  { title = "隐私与安全说明", subtitle = "数据流向" },
  { title = "退出登录", subtitle = nil },
}

step("打开我的页面", function()
  router.showTab("profile")
  check("我的 tab 已显示", router.currentKey == "profile", tostring(router.currentKey))
end)

step("我的页面列表条目检查", function()
  local view = router.current.view
  local titleMissing, subtitleMissing, clickMissing = {}, {}, {}

  for _, item in ipairs(PROFILE_ITEMS) do
    local title = findText(view, item.title)
    if title == nil then
      titleMissing[#titleMissing + 1] = item.title .. "(缺失)"
    elseif title.width <= 0 or title.height <= 0 then
      titleMissing[#titleMissing + 1] = item.title .. "(无尺寸)"
    end
    if item.subtitle ~= nil then
      local subtitle = findText(view, item.subtitle)
      if subtitle == nil or subtitle.width <= 0 then
        subtitleMissing[#subtitleMissing + 1] = item.title
      end
    end
    if item.title ~= "退出登录" then
      local target = title and clickableAncestor(title.view) or nil
      if target == nil then clickMissing[#clickMissing + 1] = item.title end
    end
  end

  check("全部 8 个条目标题可见且有尺寸", #titleMissing == 0, table.concat(titleMissing, ", "))
  check("带副标题的条目副标题可见", #subtitleMissing == 0, table.concat(subtitleMissing, ", "))
  check("条目点击区域完整", #clickMissing == 0, table.concat(clickMissing, ", "))

  -- v0.2.3：Leading Icon 容器从 40dp 缩小到 24dp（图标本身也 24dp）
  local iconHolders, legacyHolders = 0, 0
  walk(view, function(node)
    if math.abs(widthOf(node) - dp(24)) <= 2 and math.abs(heightOf(node) - dp(24)) <= 2 then
      iconHolders = iconHolders + 1
    end
    -- 只统计列表项的图标容器（FrameLayout 持有者）；
    -- SwipeRefreshLayout 自带的 CircleImageView 也是 40dp，不能算进来
    if string.find(classOf(node), "FrameLayout", 1, true) ~= nil
      and math.abs(widthOf(node) - dp(40)) <= 2 and math.abs(heightOf(node) - dp(40)) <= 2 then
      legacyHolders = legacyHolders + 1
    end
  end)
  check("列表项图标容器为 24dp", iconHolders >= 7, "匹配数=" .. iconHolders)
  check("不再存在 40dp 图标容器", legacyHolders == 0, "旧尺寸个数=" .. legacyHolders)

  local exitButton = findText(view, "退出登录")
  check("退出登录按钮可见", exitButton ~= nil and exitButton.width > 0,
    exitButton and (exitButton.width .. "px") or "未找到")
end)

step("点击「主题设置」条目验证交互", function()
  local title = findText(router.current.view, "主题设置")
  local target = title and clickableAncestor(title.view) or nil
  check("找到可点击的主题设置条目", target ~= nil)
  if target ~= nil then pcall(function() target.performClick() end) end
  check("点击后进入主题设置页", router.currentKey == "theme_settings",
    tostring(router.currentKey))
  router.back()
  check("返回我的页面", router.currentKey == "profile", tostring(router.currentKey))
end)

-- ===== 五、统计页面 =====

step("打开统计页", function()
  router.showTab("statistics")
  check("统计 tab 已显示", router.currentKey == "statistics", tostring(router.currentKey))
end)

step("统计页：双列卡片 / 年月筛选 / 图表", function()
  local view = router.current.view
  local labels = { "总练习次数", "答对题数", "练习天数", "拍照练习" }
  local missing = {}
  for _, label in ipairs(labels) do
    local item = findText(view, label)
    if item == nil or item.width <= 0 then missing[#missing + 1] = label end
  end
  check("四张摘要卡片标题可见", #missing == 0, table.concat(missing, ", "))

  local cards = findViewsByClass(view, "MaterialCardView")
  check("摘要卡片已渲染", #cards >= 2, "卡片数=" .. #cards)
  if #cards >= 2 then
    local w1, w2 = widthOf(cards[1]), widthOf(cards[2])
    check("两张摘要卡片宽度都 > 0", w1 > 0 and w2 > 0, string.format("%d / %d", w1, w2))
    check("两张摘要卡片宽度均衡（差值 ≤ 8dp）", math.abs(w1 - w2) <= dp(8),
      string.format("差值 %dpx", math.abs(w1 - w2)))
    check("两列布局（同一行）", cards[1].getTop() == cards[2].getTop(),
      string.format("top %d / %d", cards[1].getTop(), cards[2].getTop()))
    log(string.format("      摘要卡片实测宽度 %dpx / %dpx，屏宽 %dpx", w1, w2, screenWidth))
  end

  local yearText = findText(view, "年")
  check("年份筛选按钮文字可见", yearText ~= nil and yearText.width > 0,
    yearText and (yearText.width .. "px") or "未找到")
  local monthText = findText(view, "月")
  check("年月徽标可见", monthText ~= nil and monthText.width > 0,
    monthText and (monthText.width .. "px") or "未找到")

  local chartCount = 0
  for _, chartView in ipairs(findViewsByClass(view, "android.widget.ImageView")) do
    if widthOf(chartView) >= dp(200) then chartCount = chartCount + 1 end
  end
  check("柱状图 / 折线图保持完整宽度", chartCount >= 2, "宽图表数=" .. chartCount)

  local scroll = findViewsByClass(view, "NestedScrollView")[1]
  check("统计页内容高于视口（可滚动）", scroll ~= nil and childCount(scroll) == 1
    and heightOf(childAt(scroll, 0)) > scroll.getMeasuredHeight(),
    scroll and (heightOf(childAt(scroll, 0)) .. "px 内容高 / "
      .. scroll.getMeasuredHeight() .. "px 视口") or "未找到滚动容器")
  if scroll ~= nil then
    local before = scroll.getScrollY()
    pcall(function() scroll.scrollTo(0, dp(200)) end)
    check("统计页可以上下滚动", scroll.getScrollY() > before,
      string.format("%d -> %d", before, scroll.getScrollY()))
  end
end)

step("统计页：320dp 窄屏退化为单列", function()
  local originalWidthDp = kit.windowWidthDp
  kit.windowWidthDp = function() return 320 end
  local ok, page = pcall(function()
    local statisticsPage = require("app.ui.pages.statistics").create()
    -- 桩数据同步回调，onShow 内部即完成渲染
    if statisticsPage.onShow ~= nil then statisticsPage.onShow() end
    return statisticsPage
  end)
  kit.windowWidthDp = originalWidthDp
  check("窄屏下统计页可以创建并渲染", ok and page ~= nil, ok and "" or tostring(page))
  if not ok or page == nil then return end

  local host = measureAt(page.view, dp(320), "at_most")
  check("窄屏测量成功", host ~= nil)
  if host == nil then return end

  local cards = findViewsByClass(host, "MaterialCardView")
  local widest, zeroWidth = 0, 0
  for _, card in ipairs(cards) do
    local w = widthOf(card)
    if w > widest then widest = w end
    if w <= 0 then zeroWidth = zeroWidth + 1 end
  end
  check("窄屏下卡片不会变成零宽", zeroWidth == 0 and #cards > 0,
    string.format("卡片 %d 张，零宽 %d 张", #cards, zeroWidth))
  check("窄屏下卡片接近可用宽度", widest >= dp(280),
    string.format("最宽卡片 %dpx（320dp 屏可用约 288dp）", widest))
  if #cards >= 2 then
    check("窄屏下摘要卡片改为单列（上下排列）",
      cards[1].getTop() ~= cards[2].getTop(),
      string.format("top %d / %d", cards[1].getTop(), cards[2].getTop()))
  end
end)

-- ===== 六、组件级实测（320dp / 放大字体） =====

step("列表项组件：当前屏宽实测", function()
  local item = kit.listItem({
    icon = "qr_code",
    title = "Auth 迁移",
    subtitle = "生成一次性二维码，把登录状态迁移到其他设备",
    showChevron = true,
    onClick = function() end,
  })
  local host = measureAt(item, screenWidth)
  check("列表项测量成功", host ~= nil)
  if host == nil then return end
  local title = findText(host, "Auth 迁移")
  local subtitle = findText(host, "生成一次性二维码")
  local chevron = findViewsByClass(host, "android.widget.ImageView")[1]
  check("列表项标题宽度 > 0", title ~= nil and title.width > 0,
    title and (title.width .. "px") or "未找到")
  check("列表项副标题宽度 > 0", subtitle ~= nil and subtitle.width > 0,
    subtitle and (subtitle.width .. "px") or "未找到")
  check("列表项右侧箭头可见", chevron ~= nil and widthOf(chevron) > 0,
    chevron and (widthOf(chevron) .. "px") or "未找到")
  check("列表项高度满足点击区域（≥ 44dp）", heightOf(host) >= dp(44),
    heightOf(host) .. "px")
end)

step("列表项 / 页头 / 分组标题：320dp 实测", function()
  local width320 = dp(320)

  local item = kit.listItem({
    icon = "lock",
    title = "登录凭据",
    subtitle = "Token 保存在系统 Keystore 加密存储中，不会明文落盘",
    showChevron = true,
    onClick = function() end,
  })
  local host = measureAt(item, width320)
  local title = host and findText(host, "登录凭据") or nil
  local subtitle = host and findText(host, "Token 保存在系统") or nil
  check("320dp：列表项标题宽度 > 0", title ~= nil and title.width > 0,
    title and (title.width .. "px") or "未找到")
  check("320dp：列表项副标题宽度 > 0", subtitle ~= nil and subtitle.width > 0,
    subtitle and (subtitle.width .. "px") or "未找到")

  local header = kit.pageHeader("我的", "账号与设置", {
    kit.iconButton("refresh", { onClick = function() end }),
  })
  local headerHost = measureAt(header, width320)
  local headerTitle = headerHost and findText(headerHost, "我的") or nil
  local headerSubtitle = headerHost and findText(headerHost, "账号与设置") or nil
  check("320dp：页头标题宽度 > 0", headerTitle ~= nil and headerTitle.width > 0,
    headerTitle and (headerTitle.width .. "px") or "未找到")
  check("320dp：页头副标题宽度 > 0", headerSubtitle ~= nil and headerSubtitle.width > 0,
    headerSubtitle and (headerSubtitle.width .. "px") or "未找到")
  check("320dp：页头右侧操作按钮仍完整显示",
    headerHost ~= nil and findViewsByClass(headerHost, "MaterialButton")[1] ~= nil)

  local section = kit.sectionTitle("账号", "查看全部", function() end)
  local sectionHost = measureAt(section, width320)
  local sectionTitle = sectionHost and findText(sectionHost, "账号") or nil
  local sectionAction = sectionHost and findText(sectionHost, "查看全部") or nil
  check("320dp：分组标题宽度 > 0", sectionTitle ~= nil and sectionTitle.width > 0,
    sectionTitle and (sectionTitle.width .. "px") or "未找到")
  check("320dp：分组右侧操作文字宽度 > 0", sectionAction ~= nil and sectionAction.width > 0,
    sectionAction and (sectionAction.width .. "px") or "未找到")
end)

step("字体缩放 1.3 倍实测", function()
  local metrics = activity.getResources().getDisplayMetrics()
  local originalScaled = nil
  pcall(function() originalScaled = metrics.scaledDensity end)
  pcall(function() metrics.scaledDensity = metrics.density * 1.3 end)

  local item = kit.listItem({
    icon = "palette",
    title = "主题设置",
    subtitle = "跟随系统 · 动态取色",
    showChevron = true,
    onClick = function() end,
  })
  local host = measureAt(item, dp(360))
  local title = host and findText(host, "主题设置") or nil
  local subtitle = host and findText(host, "跟随系统 · 动态取色") or nil
  check("放大字体：列表项标题仍可见", title ~= nil and title.width > 0,
    title and (title.width .. "px") or "未找到")
  check("放大字体：列表项副标题仍可见", subtitle ~= nil and subtitle.width > 0,
    subtitle and (subtitle.width .. "px") or "未找到")

  local header = kit.pageHeader("统计", "你的练习与学习数据", {
    kit.iconButton("refresh", { onClick = function() end }),
  })
  local headerHost = measureAt(header, dp(360))
  local headerSubtitle = headerHost and findText(headerHost, "你的练习与学习数据") or nil
  check("放大字体：页头副标题仍可见", headerSubtitle ~= nil and headerSubtitle.width > 0,
    headerSubtitle and (headerSubtitle.width .. "px") or "未找到")

  if originalScaled ~= nil then
    pcall(function() metrics.scaledDensity = originalScaled end)
  end
end)

-- ===== 七、文字与背景对比度（浅色 / 深色模式通用） =====

local function luminanceOf(colorInt)
  local value = theme.unsigned(colorInt)
  local r = math.floor(value / 65536) % 256
  local g = math.floor(value / 256) % 256
  local b = value % 256
  return 0.299 * r + 0.587 * g + 0.114 * b
end

-- 取 drawable 的填充色（int）。
-- API 24+ 的 GradientDrawable.getColor() 返回 ColorStateList，直接 tonumber 会得到 nil，
-- 必须再取一次 defaultColor；MaterialCardView 的 MaterialShapeDrawable 另外暴露 fillColor。
local function drawableColor(drawable)
  local ok, value = pcall(function() return drawable.getColor() end)
  if ok and value ~= nil then
    if type(value) == "number" then return value end
    local okDefault, defaultColor = pcall(function() return value.getDefaultColor() end)
    if okDefault and type(defaultColor) == "number" then return defaultColor end
  end
  local okFill, fill = pcall(function() return drawable.getFillColor() end)
  if okFill and fill ~= nil then
    if type(fill) == "number" then return fill end
    local okDefault, defaultColor = pcall(function() return fill.getDefaultColor() end)
    if okDefault and type(defaultColor) == "number" then return defaultColor end
  end
  return nil
end

-- 返回 { luminance, color, source }；source 用于诊断（View 类名 / drawable 类名）
local function backgroundInfo(view)
  local current = view
  for _ = 1, 14 do
    if current == nil then return nil end
    local ok, drawable = pcall(function() return current.getBackground() end)
    if ok and drawable ~= nil then
      local colorValue = drawableColor(drawable)
      -- 取不到颜色说明不是纯色填充，继续向父容器找真正的不透明背景，
      -- 避免把透明背景当成“黑色背景”而误报对比度问题。
      if colorValue ~= nil and colorValue ~= 0 then
        local alpha = math.floor(theme.unsigned(colorValue) / 0x1000000) % 256
        if alpha > 200 then
          return {
            luminance = luminanceOf(colorValue),
            color = colorValue,
            source = classOf(current) .. "/" .. classOf(drawable),
          }
        end
      end
    end
    local okParent, parent = pcall(function() return current.getParent() end)
    if not okParent then return nil end
    current = parent
  end
  return nil
end

step("文字与背景对比度（当前主题模式）", function()
  local view = router.current.view
  local sampled, lowContrast, samples = 0, {}, {}
  for _, item in ipairs(collectTexts(view)) do
    if item.width > 0 then
      local okColor, textColor = pcall(function() return item.view.getCurrentTextColor() end)
      local background = backgroundInfo(item.view)
      if okColor and textColor ~= nil and background ~= nil then
        sampled = sampled + 1
        local delta = math.abs(luminanceOf(textColor) - background.luminance)
        if delta < 24 then
          lowContrast[#lowContrast + 1] = string.format("%s text=#%08X bg=#%08X Δ=%.1f (%s)",
            item.text:sub(1, 16), theme.unsigned(textColor),
            theme.unsigned(background.color), delta, background.source)
        end
        if delta < 70 and #samples < 6 then
          samples[#samples + 1] = string.format("%s text=#%08X bg=#%08X Δ=%.1f (%s)",
            item.text:sub(1, 16), theme.unsigned(textColor),
            theme.unsigned(background.color), delta, background.source)
        end
      end
    end
  end
  log(string.format("      主题色对：secondaryContainer=#%08X onSecondaryContainer=#%08X",
    theme.unsigned(colors.secondaryContainer), theme.unsigned(colors.onSecondaryContainer)))
  for _, sample in ipairs(samples) do log("      SAMPLE " .. sample) end
  check("可对比度的文字样本数量足够", sampled >= 8, "样本数=" .. sampled)
  check("文字与背景对比度正常（无同色文字）", #lowContrast == 0,
    table.concat(lowContrast, "; "))
  log(string.format("      当前模式：%s（另一模式需真机切换后复测）", tostring(theme.mode())))
end)

-- ===== 八、v0.2.3：Leading Icon / 卡片外边距 / 统计页 / 导航图标 / 转场 =====

-- 视图在页面内的绝对左坐标（累加父容器的 getLeft，直到页面根视图）
local function absoluteLeft(view, root)
  local x, current = 0, view
  for _ = 1, 40 do
    if current == nil then break end
    local okSame, same = pcall(function() return current.equals(root) end)
    if okSame and same == true then break end
    local okLeft, left = pcall(function() return current.getLeft() end)
    if okLeft and left ~= nil then x = x + left end
    current = parentOf(current)
  end
  return x
end

local function contentOf(pageView)
  local scroll = findViewsByClass(pageView, "NestedScrollView")[1]
  if scroll == nil then return nil end
  return childAt(scroll, 0)
end

step("v0.2.3 列表项 Leading Icon：24dp 容器 + 24dp 图标 + 16dp 间距", function()
  local item = kit.listItem({
    icon = "lock",
    title = "登录凭据",
    subtitle = "Token 保存在系统 Keystore 加密存储中，不会明文落盘",
    showChevron = true,
    onClick = function() end,
  })
  local host = measureAt(item, screenWidth)
  check("列表项测量成功", host ~= nil)
  if host == nil then return end

  local title = findText(host, "登录凭据")
  check("标题可见且有尺寸", title ~= nil and title.width > 0 and title.height > 0,
    title and (title.width .. "x" .. title.height) or "未找到")
  local subtitle = findText(host, "Token 保存在系统")
  check("副标题可见且有尺寸", subtitle ~= nil and subtitle.width > 0,
    subtitle and (subtitle.width .. "px") or "未找到")

  local iconView = nil
  for _, view in ipairs(findViewsByClass(host, "android.widget.ImageView")) do
    if math.abs(widthOf(view) - dp(24)) <= 2 and math.abs(heightOf(view) - dp(24)) <= 2 then
      iconView = view
      break
    end
  end
  check("图标尺寸为 24dp", iconView ~= nil,
    iconView and (widthOf(iconView) .. "px") or "未找到")

  local holder = iconView and parentOf(iconView) or nil
  check("图标容器为 24dp", holder ~= nil
    and math.abs(widthOf(holder) - dp(24)) <= 2 and math.abs(heightOf(holder) - dp(24)) <= 2,
    holder and (widthOf(holder) .. "x" .. heightOf(holder)) or "未找到")

  local textHolder = title and parentOf(title.view) or nil
  if holder ~= nil and textHolder ~= nil then
    local gap = textHolder.getLeft() - holder.getRight()
    check("图标与文字间距为 16dp", math.abs(gap - dp(16)) <= dp(2), gap .. "px")
    check("正文左边缘落在 56dp MD3 keyline",
      math.abs(textHolder.getLeft() - dp(56)) <= dp(2), textHolder.getLeft() .. "px")
  end

  check("双行列表项高度 ≥ 72dp", heightOf(host) >= dp(72), heightOf(host) .. "px")
  local okClickable = false
  pcall(function() okClickable = item.isClickable() and item.hasOnClickListeners() end)
  check("整行仍是点击区域（未因缩小图标容器而缩小触控区）", okClickable,
    "height=" .. heightOf(host) .. "px")

  local single = kit.listItem({ icon = "history", title = "更新日志", onClick = function() end })
  local singleHost = measureAt(single, screenWidth)
  check("单行列表项高度 ≥ 56dp", singleHost ~= nil and heightOf(singleHost) >= dp(56),
    singleHost and (heightOf(singleHost) .. "px") or "未测量")
end)

step("v0.2.3 切到我的页面", function()
  router.showTab("profile")
  check("我的 tab 已显示", router.currentKey == "profile", tostring(router.currentKey))
end)

step("v0.2.3 我的页面：卡片外边距 / 分组间距 / 分栏层次", function()
  local view = router.current.view
  local content = contentOf(view)
  check("滚动内容容器存在", content ~= nil)
  if content == nil then return end

  local cards = {}
  for index = 0, childCount(content) - 1 do
    local child = childAt(content, index)
    if child ~= nil and string.find(classOf(child), "MaterialCardView", 1, true) ~= nil then
      cards[#cards + 1] = child
    end
  end
  check("我的页面至少有 4 张分组卡片", #cards >= 4, "卡片数=" .. #cards)

  local badEdge = {}
  for index, card in ipairs(cards) do
    local left = absoluteLeft(card, view)
    local right = left + widthOf(card)
    if left < dp(12) or right > screenWidth - dp(12) then
      badEdge[#badEdge + 1] = string.format("卡片%d left=%d right=%d", index, left, right)
    end
  end
  check("卡片左右外边距真正生效（不再贴屏幕边缘）", #badEdge == 0,
    table.concat(badEdge, "; ") .. (screenWidth and (" | 屏宽 " .. screenWidth) or ""))
  if cards[1] ~= nil then
    local left = absoluteLeft(cards[1], view)
    check("账号卡片左边缘为 16dp", math.abs(left - dp(16)) <= dp(2), left .. "px")
  end

  for index = 2, #cards do
    local gap = cards[index].getTop() - cards[index - 1].getBottom()
    check(string.format("分组卡片 %d 与上一张之间有呼吸间距（≥ 8dp）", index), gap >= dp(8),
      gap .. "px")
  end

  -- 同一组内用 Divider 分隔，而不是拆成多张卡片
  local dividers = findViewsByClass(view, "MaterialDivider")
  check("同组列表项之间使用 Divider 分隔", #dividers >= 2, "分割线=" .. #dividers)
end)

step("v0.2.3 切到统计页", function()
  router.showTab("statistics")
  check("统计 tab 已显示", router.currentKey == "statistics", tostring(router.currentKey))
end)

step("v0.2.3 统计页：年份按钮不裁切、月份栏已精简", function()
  local view = router.current.view
  local yearButtons = buttonsMatching(view, "MaterialButton", "年")
  check("年份选择按钮存在且只有一个", #yearButtons == 1, "个数=" .. #yearButtons)
  local button = yearButtons[1]
  if button ~= nil then
    check("年份按钮高度 ≥ 48dp（稳定触控高度）", heightOf(button) >= dp(48),
      heightOf(button) .. "px")
    local layoutHeight, padTop, padBottom = 0, 0, 0
    pcall(function() layoutHeight = button.getLayout().getHeight() end)
    pcall(function()
      padTop = button.getPaddingTop()
      padBottom = button.getPaddingBottom()
    end)
    local contentHeight = heightOf(button) - padTop - padBottom
    check("年份文字未被裁切（内容区高度 ≥ 文本行高）",
      layoutHeight > 0 and contentHeight >= layoutHeight,
      string.format("按钮 %dpx，padding %d+%d，文本行高 %dpx",
        heightOf(button), padTop, padBottom, layoutHeight))
    check("年份按钮为 outlined 样式且文字垂直居中",
      contentHeight >= layoutHeight and contentHeight - layoutHeight >= 0,
      "内容区余量 " .. (contentHeight - layoutHeight) .. "px")
  end

  local badge = findText(view, " 年 ")
  local badgeView = badge and badge.view or nil
  local badgeRow = badgeView and parentOf(badgeView) or nil
  if badgeRow ~= nil and childCount(badgeRow) <= 1 then badgeRow = parentOf(badgeRow) end
  check("月份选择栏存在", badgeRow ~= nil)
  if badgeRow ~= nil then
    local monthButtons = buttonsMatching(badgeRow, "MaterialButton")
    check("月份选择栏只剩 1 个图标按钮（重复刷新已移除）", #monthButtons == 1,
      "个数=" .. #monthButtons)
  end

  local iconOnly = buttonsMatching(view, "MaterialButton")
  check("统计页图标按钮总数为 2（页头刷新 + 月份选择）", #iconOnly == 2, "个数=" .. #iconOnly)

  local content = contentOf(view)
  local header = content and childAt(content, 0) or nil
  local headerButtons = header and buttonsMatching(header, "MaterialButton") or {}
  check("页头保留唯一的刷新入口", #headerButtons == 1, "个数=" .. #headerButtons)
end)

step("v0.2.3 统计页：卡片间距 12dp、图表不贴边、无横向溢出", function()
  local view = router.current.view
  -- 先确保页面处于「已测量并布局」的状态：切页刚完成时若布局还没跑，
  -- 读到的 getLeft/getRight 都是 0，会让间距断言得出无意义的负值。
  local widthSpec = MeasureSpec.makeMeasureSpec(screenWidth, MeasureSpec.EXACTLY)
  local heightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
  pcall(function()
    view.measure(widthSpec, heightSpec)
    view.layout(0, 0, view.getMeasuredWidth(), view.getMeasuredHeight())
  end)
  check("统计页已测量（宽度 > 0）", widthOf(view) > 0, widthOf(view) .. "px")

  local cards = findViewsByClass(view, "MaterialCardView")
  check("统计页卡片已渲染", #cards >= 4, "卡片数=" .. #cards)
  for index, card in ipairs(cards) do
    log(string.format("      卡片%d %dx%d L=%d T=%d R=%d B=%d", index,
      widthOf(card), heightOf(card), card.getLeft(), card.getTop(),
      card.getRight(), card.getBottom()))
  end

  local badEdge = {}
  for index, card in ipairs(cards) do
    local left = absoluteLeft(card, view)
    local right = left + widthOf(card)
    if left < dp(12) or right > screenWidth - dp(12) then
      badEdge[#badEdge + 1] = string.format("卡片%d left=%d right=%d", index, left, right)
    end
  end
  check("所有统计卡片左右边距 ≥ 12dp（图表不贴屏幕边缘）", #badEdge == 0,
    table.concat(badEdge, "; "))

  if #cards >= 2 then
    local gap = cards[2].getLeft() - cards[1].getRight()
    check("双列卡片之间间距为 12dp", math.abs(gap - dp(12)) <= dp(2), gap .. "px")
  end
  if #cards >= 3 then
    local row1, row2 = parentOf(cards[1]), parentOf(cards[3])
    if row1 ~= nil and row2 ~= nil then
      local rowGap = row2.getTop() - row1.getBottom()
      check("两行摘要卡片之间间距为 12dp", math.abs(rowGap - dp(12)) <= dp(2), rowGap .. "px")
    end
  end

  local chartCount, chartOverflow = 0, 0
  for _, chartView in ipairs(findViewsByClass(view, "android.widget.ImageView")) do
    if widthOf(chartView) >= dp(200) then
      chartCount = chartCount + 1
      local left = absoluteLeft(chartView, view)
      if left + widthOf(chartView) > screenWidth then chartOverflow = chartOverflow + 1 end
    end
  end
  check("柱状图 / 折线图完整渲染", chartCount >= 2, "宽图表数=" .. chartCount)
  check("图表未超出屏幕宽度", chartOverflow == 0, "溢出数=" .. chartOverflow)
end)

step("v0.2.3 底部导航：选中填充 / 未选中描边", function()
  local iconsModule = require "app.ui.icons"
  local tabIconNames = {
    { filled = "assignment", outline = "assignment_outline" },
    { filled = "notifications", outline = "notifications_outline" },
    { filled = "insights", outline = "insights_outline" },
    { filled = "person", outline = "person_outline" },
  }
  local missing = {}
  for _, pair in ipairs(tabIconNames) do
    if not iconsModule.has(pair.filled) then missing[#missing + 1] = pair.filled end
    if not iconsModule.has(pair.outline) then missing[#missing + 1] = pair.outline end
  end
  check("四套填充 / 描边图标定义齐全", #missing == 0, table.concat(missing, ", "))

  local shellModule = require "app.ui.shell"
  local nav = shellModule.bottomNav
  check("底部导航已创建", nav ~= nil)
  if nav == nil then return end
  local menu = nav.getMenu()
  check("底部导航有 4 个入口", menu.size() == 4, "size=" .. tostring(menu.size()))

  pcall(function() nav.setSelectedItemId(1) end)
  -- 必须取当前主题色板：脚本加载时（theme.bootstrap 之前）缓存下来的 colors 已经过期，
  -- 用过期色值算出来的位图身份与实际菜单图标不一致，会误报。
  local liveColors = theme.colors()
  local filledHome = bitmapId(iconsModule.get("assignment", 24, liveColors.onSecondaryContainer))
  local outlineHome = bitmapId(iconsModule.get("assignment_outline", 24, liveColors.onSurfaceVariant))
  local selectedId = bitmapId(menu.findItem(1).getIcon())
  local unselectedId = bitmapId(menu.findItem(2).getIcon())
  local outlineBell = bitmapId(iconsModule.get("notifications_outline", 24, liveColors.onSurfaceVariant))
  local filledBell = bitmapId(iconsModule.get("notifications", 24, liveColors.onSecondaryContainer))

  check("选中项使用填充图标", selectedId ~= nil and selectedId == filledHome,
    tostring(selectedId) .. " / 期望 " .. tostring(filledHome))
  check("未选中项使用描边图标（铃铛不再用填充版）",
    unselectedId ~= nil and unselectedId == outlineBell,
    tostring(unselectedId) .. " / 期望 " .. tostring(outlineBell))
  check("选中与未选中图标确实不同", selectedId ~= unselectedId,
    tostring(selectedId) .. " / " .. tostring(unselectedId))

  local sizeOk = true
  for index = 1, 4 do
    local ok, drawable = pcall(function() return menu.findItem(index).getIcon() end)
    if not ok or drawable == nil then
      sizeOk = false
    else
      local okBounds, bounds = pcall(function() return drawable.getBounds() end)
      if not okBounds or bounds == nil
        or math.abs(bounds.width() - dp(24)) > 2 or math.abs(bounds.height() - dp(24)) > 2 then
        sizeOk = false
      end
    end
  end
  check("四个导航图标视觉尺寸一致（24dp 逻辑网格）", sizeOk)

  pcall(function() nav.setSelectedItemId(2) end)
  check("切换到通知后 selectedItemId 正确", nav.getSelectedItemId() == 2,
    tostring(nav.getSelectedItemId()))
  check("切换后通知变为填充态",
    bitmapId(menu.findItem(2).getIcon()) == filledBell)
  check("切换后作业变为描边态",
    bitmapId(menu.findItem(1).getIcon()) == outlineHome)
end)

step("v0.2.3 转场：能力探测与四个主页快速连点", function()
  local motion = require "app.ui.motion"
  local info = motion.describe()
  log(string.format("      转场模式=%s FadeThrough=%s SharedAxis=%s TransitionManager=%s 动画缩放=%s",
    tostring(info.mode), tostring(info.materialFadeThrough), tostring(info.materialSharedAxis),
    tostring(info.transitionManager), tostring(info.animatorScale)))
  check("Material 官方转场类可用",
    info.materialFadeThrough and info.materialSharedAxis and info.transitionManager,
    tostring(info.mode))
  check("系统动画缩放允许播放转场", info.animatorScale ~= nil and info.animatorScale > 0.01,
    tostring(info.animatorScale))

  local keys = { "homework", "notifications", "statistics", "profile" }
  local failed, stacked = {}, {}
  for _, key in ipairs(keys) do
    local ok = pcall(function() router.showTab(key) end)
    if not ok then failed[#failed + 1] = key end
    if childCount(router.container) ~= 1 then
      stacked[#stacked + 1] = key .. ":" .. childCount(router.container)
    end
  end
  check("快速连续切换 4 个主页不抛异常", #failed == 0, table.concat(failed, ", "))
  check("快速连续切换后不出现视图叠加", #stacked == 0, table.concat(stacked, ", "))
  check("最终停留在「我的」", router.currentKey == "profile", tostring(router.currentKey))
end)

step("v0.2.3 转场结束后页面可交互（无空白 / 无失焦）", function()
  local child = childAt(router.container, 0)
  check("容器内页面视图尺寸正常（无空白）",
    child ~= nil and widthOf(child) > 0 and heightOf(child) > 0,
    child and (widthOf(child) .. "x" .. heightOf(child)) or "无子视图")
  local title = findText(router.current.view, "主题设置")
  local target = title and clickableAncestor(title.view) or nil
  check("转场后条目仍可点击", target ~= nil)
  if target ~= nil then pcall(function() target.performClick() end) end
  check("点击后进入主题设置（转场未阻塞输入）", router.currentKey == "theme_settings",
    tostring(router.currentKey))
end)

step("v0.2.3 二级页连续打开（SharedAxis forward）", function()
  router.push(require("app.ui.pages.about").create())
  router.push(require("app.ui.pages.security").create())
  check("连续压栈后容器内只有 1 个页面视图", childCount(router.container) == 1,
    "childCount=" .. childCount(router.container))
  check("当前为隐私与安全页", router.currentKey == "security", tostring(router.currentKey))
end)

step("v0.2.3 多层返回（SharedAxis backward）", function()
  local okBack1 = router.back()
  local okBack2 = router.back()
  local okBack3 = router.back()
  check("三次返回都被处理", okBack1 and okBack2 and okBack3,
    tostring(okBack1) .. "/" .. tostring(okBack2) .. "/" .. tostring(okBack3))
  check("返回后容器内只有 1 个页面视图", childCount(router.container) == 1,
    "childCount=" .. childCount(router.container))
  check("返回到「我的」页面", router.currentKey == "profile", tostring(router.currentKey))
  local child = childAt(router.container, 0)
  check("返回后页面尺寸正常（非空白）", child ~= nil and widthOf(child) > 0,
    child and (widthOf(child) .. "px") or "无子视图")
end)

step("v0.2.3 320dp + 1.3 倍字体：年份按钮仍不裁切", function()
  local metrics = activity.getResources().getDisplayMetrics()
  local originalScaled = nil
  pcall(function() originalScaled = metrics.scaledDensity end)
  pcall(function() metrics.scaledDensity = metrics.density * 1.3 end)

  local button = kit.button("2026 年", {
    style = "outlined",
    height = "48dp",
    size = kit.TYPOGRAPHY.body,
  })
  local host = measureAt(button, dp(320))

  if originalScaled ~= nil then pcall(function() metrics.scaledDensity = originalScaled end) end

  check("320dp/1.3 字体：按钮测量成功", host ~= nil and heightOf(button) >= dp(48),
    button and (heightOf(button) .. "px") or "未测量")
  local layoutHeight, padTop, padBottom = 0, 0, 0
  pcall(function() layoutHeight = button.getLayout().getHeight() end)
  pcall(function()
    padTop = button.getPaddingTop()
    padBottom = button.getPaddingBottom()
  end)
  check("320dp/1.3 字体：年份文字不超出内容区",
    layoutHeight > 0 and heightOf(button) - padTop - padBottom >= layoutHeight,
    string.format("%d - %d - %d vs 行高 %d", heightOf(button), padTop, padBottom, layoutHeight))
end)

-- ===== 启动 =====

log("VanthinkMD3 UI 回归诊断")
log(string.format("设备：%sdp 宽，%ddpi",
  tostring(activity.getResources().getConfiguration().screenWidthDp),
  activity.getResources().getDisplayMetrics().densityDpi))
log("说明：服务层全部使用桩数据，不访问网络。")
flush()

activity.delay(600, runNext)
