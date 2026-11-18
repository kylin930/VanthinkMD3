-- 通知中心：分页列表、未读状态、单条已读、批量已读、详情页。
-- 渲染策略同作业页：外壳与头部只构建一次，刷新只重建列表区。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local state = require "app.state"
local noticeService = require "app.services.notice"
local formatter = require "app.utils.formatter"

local M = {}

local function openDetail(item, onRead)
  local colors = theme.colors()
  local shell = kit.scrollPage({})
  local sub = router.subPage({
    title = "通知详情",
    content = shell.root,
  })

  local sender = type(item.sender) == "table" and item.sender.nickname or "系统"
  shell.add(kit.spacer(8))
  shell.add(kit.card({
    kit.row({
      kit.badge(sender, {
        background = colors.primaryContainer,
        color = colors.onPrimaryContainer,
      }),
      kit.column({}, { width = "0dp", weight = 1 }),
      kit.text(formatter.friendlyTime(item.created_at), {
        size = kit.TYPOGRAPHY.label,
        color = colors.outline,
      }),
    }, { width = "match" }),
    kit.spacer(12),
    kit.text(tostring(item.content or ""), {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      width = "match",
    }),
  }, { marginHorizontal = 16, padding = 18 }))
  shell.add(kit.spacer(24))

  return {
    key = "notice_detail",
    view = sub.root,
    onShow = function()
      if noticeService.isUnread(item) then
        noticeService.markRead({ item.id }, function(ok)
          if ok then
            item.has_read = 1
            if onRead then onRead() end
          end
        end)
      end
    end,
  }
end

function M.create()
  local colors = theme.colors()
  local page = {
    key = "notifications",
    list = {},
    pageNo = 1,
    count = 0,
    hasMore = true,
    loading = false,
    loaded = false,
    error = nil,
  }

  local shell = kit.scrollPage({
    onRefresh = function() page.reload() end,
    onLoadMore = function() page.loadMore() end,
  })
  page.view = shell.root

  local subtitleLabel = kit.text("", {
    size = kit.TYPOGRAPHY.label,
    color = colors.onSurfaceVariant,
  })
  local body = kit.column({}, { width = "match" })

  shell.add(kit.pageHeader("通知", nil, {
    kit.iconButton("done_all", { onClick = function() page.markAllRead() end }),
    kit.iconButton("refresh", { onClick = function() page.reload() end }),
  }))
  shell.add(kit.row({
    subtitleLabel,
    kit.column({}, { width = "0dp", weight = 1 }),
  }, { width = "match", paddingStart = 20, paddingEnd = 20, paddingBottom = 8 }))
  shell.add(kit.spacer(4))
  shell.add(body)

  local function unreadCount()
    local total = 0
    for _, item in ipairs(page.list) do
      if noticeService.isUnread(item) then total = total + 1 end
    end
    return total
  end

  local function buildItem(item)
    local unread = noticeService.isUnread(item)
    local sender = type(item.sender) == "table" and item.sender.nickname or "系统"
    local children = {
      kit.row({
        kit.column({
          kit.text(sender, {
            size = kit.TYPOGRAPHY.label,
            color = unread and colors.primary or colors.onSurfaceVariant,
            bold = unread,
          }),
        }, { width = "0dp", weight = 1 }),
        kit.text(formatter.friendlyTime(item.created_at), {
          size = kit.TYPOGRAPHY.label,
          color = colors.outline,
        }),
      }, { width = "match" }),
      kit.spacer(6),
      kit.text(tostring(item.content or ""), {
        size = kit.TYPOGRAPHY.body,
        color = colors.onSurface,
        maxLines = 4,
        width = "match",
      }),
    }
    if unread then
      children[#children + 1] = kit.spacer(8)
      children[#children + 1] = kit.badge("未读", {
        background = colors.errorContainer,
        color = colors.onErrorContainer,
      })
    end

    return kit.card(children, {
      marginHorizontal = 16,
      marginTop = 8,
      background = unread and colors.surfaceContainerHigh or colors.surfaceContainerLow,
      onClick = function()
        router.push(openDetail(item, function()
          state.setUnreadCount(unreadCount())
          subtitleLabel.setText(string.format("共 %s 条 · 未读 %d 条",
            formatter.int(page.count), unreadCount()))
          page.renderBody()
        end))
      end,
    })
  end

  function page.renderBody()
    body.removeAllViews()
    local unread = unreadCount()
    state.setUnreadCount(unread)
    subtitleLabel.setText(string.format("共 %s 条 · 未读 %d 条", formatter.int(page.count), unread))

    if page.loading and #page.list == 0 then
      body.addView(kit.row({
        kit.spinner(24),
        kit.text("正在加载通知…", {
          size = kit.TYPOGRAPHY.body,
          color = colors.onSurfaceVariant,
          marginStart = 12,
        }),
      }, { width = "match", padding = 28, gravity = "center" }))
      return
    end

    if page.error ~= nil then
      body.addView(kit.stateView({
        icon = "cloud_off",
        title = "通知加载失败",
        message = page.error,
        actionLabel = "重试",
        actionIcon = "refresh",
        onAction = function() page.reload() end,
      }))
      return
    end

    if #page.list == 0 then
      body.addView(kit.stateView({
        icon = "notifications",
        title = "还没有通知",
        message = "老师发布通知后会显示在这里",
      }))
      return
    end

    for _, item in ipairs(page.list) do
      body.addView(buildItem(item))
    end

    if page.hasMore then
      if page.loading then
        body.addView(kit.row({
          kit.spinner(20),
          kit.text("加载更多…", {
            size = kit.TYPOGRAPHY.label,
            color = colors.onSurfaceVariant,
            marginStart = 8,
          }),
        }, { width = "match", padding = 16, gravity = "center" }))
      else
        body.addView(kit.row({
          kit.button("加载更多", {
            style = "outlined",
            height = "40dp",
            size = kit.TYPOGRAPHY.label,
            onClick = function() page.loadMore() end,
          }),
        }, { width = "match", padding = 12, gravity = "center" }))
      end
    else
      body.addView(kit.row({
        kit.text("已经到底了", { size = kit.TYPOGRAPHY.label, color = colors.outline }),
      }, { width = "match", padding = 16, gravity = "center" }))
    end
  end

  function page.render()
    page.renderBody()
  end

  function page.load(reset)
    if page.loading then return end
    if not state.isLoggedIn() then
      page.error = "登录状态已失效，请重新登录"
      page.loaded = true
      page.renderBody()
      return
    end
    page.loading = true
    if reset then
      page.pageNo = 1
      page.list = {}
      page.hasMore = true
    end
    page.error = nil
    page.renderBody()

    noticeService.fetchList({ page = page.pageNo }, function(ok, data, result)
      page.loading = false
      page.loaded = true
      shell.setRefreshing(false)
      if not ok then
        page.error = tostring(data)
        page.renderBody()
        if result ~= nil and result.kind == "auth" then
          require "app.ui.pages.login".showAuthExpired()
        end
        return
      end
      for _, item in ipairs(data.list) do
        page.list[#page.list + 1] = item
      end
      page.count = data.count
      page.hasMore = data.hasMore
      if page.hasMore then page.pageNo = page.pageNo + 1 end
      page.renderBody()
    end)
  end

  function page.reload()
    page.load(true)
  end

  function page.loadMore()
    if not page.hasMore or page.loading or page.error ~= nil then return end
    page.load(false)
  end

  -- 批量已读：只提交当前已加载的未读通知
  function page.markAllRead()
    local ids = {}
    for _, item in ipairs(page.list) do
      if noticeService.isUnread(item) then ids[#ids + 1] = item.id end
    end
    if #ids == 0 then
      dialogs.snackbar("当前没有未读通知")
      return
    end
    dialogs.confirm({
      title = "全部标为已读",
      message = string.format("将把当前列表中的 %d 条未读通知标记为已读。", #ids),
      positiveLabel = "标记已读",
      onConfirm = function()
        noticeService.markRead(ids, function(ok)
          if not ok then
            dialogs.alert("操作失败", "服务端返回错误，请稍后重试")
            return
          end
          for _, item in ipairs(page.list) do
            if noticeService.isUnread(item) then item.has_read = 1 end
          end
          page.renderBody()
          dialogs.snackbar("已标记为已读")
        end)
      end,
    })
  end

  function page.onShow()
    if not page.loaded then
      page.load(true)
    else
      page.renderBody()
    end
  end

  page.renderBody()
  return page
end

return M
