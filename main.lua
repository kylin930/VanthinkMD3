-- VanthinkMD3 入口
-- 启动顺序：主题（含深浅色 / 动态色）→ 外壳布局 → 登录态判断 → 主界面

local theme = require "app.ui.theme"
local shell = require "app.ui.shell"
local http = require "app.services.http"
local state = require "app.state"
local logger = require "app.utils.logger"

-- 动态色与深浅色必须在 setContentView 之前生效
theme.bootstrap()

-- HTTP 层注入 Token 与登录失效处理
http.setTokenProvider(function()
  return state.token
end)
http.setAuthInvalidHandler(function()
  logger.w("检测到鉴权失败（errcode 44）")
end)

-- 全局错误回调：保证崩溃时给出可读信息，而不是空白页
function onError(error, message)
  logger.e("未捕获异常: " .. tostring(error) .. " | " .. tostring(message))
  return false
end

local ok, err = xpcall(function()
  shell.init()
  shell.start()
end, function(e)
  return tostring(e) .. "\n" .. tostring(debug.traceback())
end)

if not ok then
  logger.e("启动失败: " .. tostring(err))
  pcall(function()
    local MaterialAlertDialogBuilder = luajava.bindClass(
      "com.google.android.material.dialog.MaterialAlertDialogBuilder")
    MaterialAlertDialogBuilder(activity)
      .setTitle("启动失败")
      .setMessage("应用启动时出错：\n" .. tostring(err))
      .setPositiveButton("退出", function() activity.finish() end)
      .show()
  end)
end
