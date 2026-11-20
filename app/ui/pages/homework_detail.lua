-- 作业详情页：概览信息、练习列表、练习操作入口、分享图片。

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local dialogs = require "app.ui.dialogs"
local router = require "app.router"
local homeworkService = require "app.services.homework"
local shareService = require "app.services.share"
local formatter = require "app.utils.formatter"
local practiceActions = require "app.ui.pages.practice"

local M = {}

local function infoRow(label, value, colors)
  return kit.row({
    kit.text(label, {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
    }, { width = "0dp", weight = 1 }),
  }, { width = "match" })
end

local function practiceRow(practice, index, colors, onOpen)
  local game = practice.game or {}
  local gameName = tostring(game.name or "练习")
  local standardMode = homeworkService.isStandardMode(practice)
  local voice = homeworkService.isVoicePractice(practice)

  local badges = kit.row({}, { width = "wrap", marginTop = 6 })
  if standardMode then
    badges.addView(kit.badge("达标 " .. formatter.percent((tonumber(practice.standard) or 0) * 100), {
      background = colors.tertiaryContainer,
      color = colors.onTertiaryContainer,
    }))
  end
  if voice then
    -- 横向行内的间距用 hSpacer：kit.spacer 宽度 match，会把后面的徽标挤出屏幕
    if standardMode then badges.addView(kit.hSpacer(6)) end
    badges.addView(kit.badge("语音", {
      background = colors.secondaryContainer,
      color = colors.onSecondaryContainer,
    }))
  end

  local children = {
    kit.row({
      kit.column({
        kit.text(string.format("%d. %s", index, gameName), {
          size = kit.TYPOGRAPHY.body,
          color = colors.onSurface,
          bold = true,
          maxLines = 2,
        }),
        kit.spacer(2),
        kit.text(tostring(practice.name or ""), {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
          maxLines = 2,
        }),
      }, { width = "0dp", weight = 1 }),
      kit.icon("chevron_right", 18, colors.outline),
    }, { width = "match" }),
  }
  if standardMode or voice then
    children[#children + 1] = badges
  end

  return kit.column(children, {
    width = "match",
    paddingStart = 16,
    paddingEnd = 16,
    paddingTop = 14,
    paddingBottom = 14,
    id = nil,
  }), function() onOpen(practice) end
end

function M.create(homework)
  local colors = theme.colors()
  local page = {
    key = "homework_detail",
    homework = homework,
    detail = nil,
    loading = true,
    error = nil,
  }

  local shell = kit.scrollPage({
    onRefresh = function() page.load() end,
  })

  local sub = router.subPage({
    title = homework.name or "作业详情",
    content = shell.root,
  })
  page.view = sub.root

  local progressDialog = nil

  local function showShare(url)
    local content = kit.column({
      kit.row({
        kit.spinner(20),
        kit.text("正在下载分享图片…", {
          size = kit.TYPOGRAPHY.label,
          color = colors.onSurfaceVariant,
          marginStart = 8,
        }),
      }, { width = "match", padding = 12 }),
    }, { width = "match" })

    local dialog = dialogs.custom({
      title = "作业分享",
      view = content,
      positiveLabel = "系统分享",
      negativeLabel = "关闭",
      onPositive = function()
        dialogs.snackbar("请在图片加载完成后点击分享按钮")
      end,
    })

    shareService.downloadBitmap(url, function(bitmap)
      content.removeAllViews()
      if bitmap == nil then
        content.addView(kit.stateView({
          icon = "cloud_off",
          title = "图片下载失败",
          message = "请检查网络后重试",
        }))
        return
      end

      local ImageView = luajava.bindClass("android.widget.ImageView")
      local imageView = loadlayout({
        ImageView,
        layout_width = "match",
        layout_height = "wrap",
        adjustViewBounds = true,
        scaleType = "fitCenter",
      })
      imageView.setImageBitmap(bitmap)
      content.addView(imageView)
      content.addView(kit.spacer(12))
      content.addView(kit.text("图片由服务端生成，可直接保存或分享到其他应用。", {
        size = kit.TYPOGRAPHY.label,
        color = colors.outline,
      }))

      local actions = kit.row({
        kit.button("保存图片", {
          style = "outlined",
          height = "40dp",
          size = kit.TYPOGRAPHY.label,
          onClick = function()
            local ok, message = shareService.saveToGallery(bitmap)
            dialogs.snackbar(ok and "已保存到相册" or ("保存失败：" .. tostring(message)))
          end,
        }),
        kit.button("系统分享", {
          height = "40dp",
          size = kit.TYPOGRAPHY.label,
          marginStart = 8,
          onClick = function()
            local ok, message = shareService.shareBitmap(bitmap)
            if not ok then dialogs.snackbar("分享失败：" .. tostring(message)) end
          end,
        }),
      }, { width = "match", marginTop = 8 })
      content.addView(actions)
      if dialog ~= nil then
        pcall(function() dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE).setVisibility(8) end)
      end
    end)
  end

  function page.render()
    shell.clear()
    if page.loading and page.detail == nil then
      shell.add(kit.row({
        kit.spinner(24),
        kit.text("正在加载作业详情…", {
          size = kit.TYPOGRAPHY.body,
          color = colors.onSurfaceVariant,
          marginStart = 12,
        }),
      }, { width = "match", padding = 28, gravity = "center" }))
      return
    end

    if page.error ~= nil then
      shell.add(kit.stateView({
        icon = "cloud_off",
        title = "作业详情加载失败",
        message = page.error,
        actionLabel = "重试",
        actionIcon = "refresh",
        onAction = function() page.load() end,
      }))
      return
    end

    local detail = page.detail or {}
    local teacher = detail.teacher_name or "老师"
    local className = (type(detail.vanclass) == "table" and detail.vanclass.name) or "未知班级"
    local typeName = (type(detail["type"]) == "table" and detail["type"].name) or "普通模式"
    local createdAt = formatter.friendlyTime(detail.created_at)
    local practices = detail.testbanks or {}

    shell.add(kit.spacer(8))
    shell.add(kit.card({
      kit.text(detail.name or homework.name or "作业", {
        size = kit.TYPOGRAPHY.headline,
        color = colors.onSurface,
        bold = true,
      }),
      kit.spacer(8),
      kit.text(string.format("%s 老师 · %s · %s", teacher, className, typeName), {
        size = kit.TYPOGRAPHY.label,
        color = colors.onSurfaceVariant,
      }),
      kit.spacer(4),
      kit.text("布置时间：" .. createdAt, {
        size = kit.TYPOGRAPHY.label,
        color = colors.outline,
      }),
      kit.spacer(14),
      kit.row({
        kit.column({
          kit.text(tostring(#practices), {
            size = kit.TYPOGRAPHY.headline,
            color = colors.primary,
            bold = true,
          }),
          kit.text("练习项", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
        }, { width = "0dp", weight = 1 }),
        kit.column({
          kit.text(formatter.percent(homework.completion_rate or 0), {
            size = kit.TYPOGRAPHY.headline,
            color = colors.tertiary,
            bold = true,
          }),
          kit.text("完成度", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
        }, { width = "0dp", weight = 1 }),
        kit.column({
          kit.text(tostring(homework.testbank_count or #practices), {
            size = kit.TYPOGRAPHY.headline,
            color = colors.onSurface,
            bold = true,
          }),
          kit.text("题目数", { size = kit.TYPOGRAPHY.label, color = colors.onSurfaceVariant }),
        }, { width = "0dp", weight = 1 }),
      }, { width = "match" }),
    }, { marginHorizontal = 16, padding = 18 }))

    shell.add(kit.spacer(8))
    shell.add(kit.sectionTitle("练习列表", "分享作业", function()
      page.share()
    end))

    if #practices == 0 then
      shell.add(kit.stateView({
        icon = "inbox",
        title = "该作业暂无练习项",
        message = "老师可能还在编辑，稍后再来查看",
      }))
    else
      local listChildren = {}
      for index, practice in ipairs(practices) do
        local rowView, onClick = practiceRow(practice, index, colors, function(item)
          practiceActions.showPracticeActions(page.homework, item, function() page.load() end)
        end)
        rowView.setClickable(true)
        rowView.setFocusable(true)
        rowView.setOnClickListener(function() onClick() end)
        listChildren[#listChildren + 1] = rowView
        if index < #practices then
          listChildren[#listChildren + 1] = kit.divider()
        end
      end
      shell.add(kit.card(listChildren, { marginHorizontal = 16, padding = 0 }))
    end

    shell.add(kit.spacer(16))
    shell.add(kit.text(
      "提示：练习完成记录只会按你输入的实际情况提交，应用不会代替你答题，也不会生成虚假成绩。",
      { size = kit.TYPOGRAPHY.label, color = colors.outline, maxLines = 5 }))
    shell.add(kit.spacer(24))
  end

  function page.share()
    dialogs.snackbar("正在获取分享图片…")
    shareService.fetchShareImage(page.homework.id, function(ok, urlOrMessage)
      if not ok then
        dialogs.alert("无法获取分享图片", urlOrMessage)
        return
      end
      showShare(urlOrMessage)
    end)
  end

  function page.load()
    page.loading = true
    page.error = nil
    page.render()
    homeworkService.fetchDetail(page.homework.id, function(ok, data)
      page.loading = false
      shell.setRefreshing(false)
      if not ok then
        page.error = tostring(data)
        page.render()
        return
      end
      page.detail = data
      if data.name ~= nil then
        local titleView = sub.bar.getChildAt(1)
        if titleView ~= nil then titleView.setText(tostring(data.name)) end
      end
      page.render()
    end)
  end

  function page.onShow()
    page.load()
  end

  page.render()
  return page
end

return M
