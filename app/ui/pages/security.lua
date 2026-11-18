-- 隐私与安全说明

local kit = require "app.ui.kit"
local theme = require "app.ui.theme"
local router = require "app.router"
local config = require "app.config"
local secure = require "app.storage.secure"

local M = {}

local function block(title, body, colors)
  return kit.card({
    kit.text(title, {
      size = kit.TYPOGRAPHY.body,
      color = colors.onSurface,
      bold = true,
    }),
    kit.spacer(6),
    kit.text(body, {
      size = kit.TYPOGRAPHY.label,
      color = colors.onSurfaceVariant,
      width = "match",
    }),
  }, { marginHorizontal = 16, marginTop = 8, padding = 16 })
end

function M.create()
  local colors = theme.colors()
  local shell = kit.scrollPage({})
  local sub = router.subPage({ title = "隐私与安全", content = shell.root })

  shell.add(kit.spacer(8))
  shell.add(block("登录凭据", "登录返回的 Token 写入 Android Keystore（AES/GCM）加密存储，"
    .. "偏好设置中只保存密文与 IV，不保存明文；应用不会在日志中输出 Token 或完整手机号。"
    .. (secure.isAvailable() and "" or "（注意：当前设备 Keystore 初始化失败，凭据可能无法保存。）"),
    colors))

  shell.add(block("密码处理", "密码仅用于登录请求本身，通过 HTTPS 提交给官方接口，"
    .. "不做本地存储，也不写入任何偏好设置或缓存。", colors))

  shell.add(block("网络传输", "所有请求使用 HTTPS。业务数据只发送到 " .. config.API_BASE .. "。"
    .. "Auth 迁移与版本说明使用第三方域名 " .. config.THIRD_PARTY.sourceHost
    .. "；其中 Auth 迁移会把 Token 作为查询参数发送给该服务，这在原项目中即存在，"
    .. "应用内已对此给出明确风险提示，且只在用户主动操作时调用。", colors))

  shell.add(block("本地数据", "本机仅保存：加密后的 Token、账号展示信息（昵称/ID/头像地址）、"
    .. "主题与显示偏好、上次更新的版本号。不含密码、聊天记录或作业答案。", colors))

  shell.add(block("不做的事", "不收集设备信息，不上传行为数据，不内置任何管理员密钥或 AccessKey，"
    .. "不代替用户答题或伪造成绩记录。", colors))

  shell.add(kit.spacer(24))
  return { key = "security", view = sub.root }
end

return M
