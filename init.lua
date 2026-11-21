app_name = "VanthinkMD3"
package_name = "com.xiaolin.vanthink"
ver_name = "0.2.4"
ver_code = "204"
min_sdk = "26"
target_sdk = "33"
-- 发布构建：关闭 debug 标志，避免暴露调试能力
debug_mode = false
-- 无 ActionBar 的 Material 3 主题；页面自行绘制返回栏与底部导航
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
-- 仅需联网权限：登录/作业/通知/统计走 HTTPS；
-- 分享图片保存使用 MediaStore（Android 10+ 免存储权限）。
user_permission = {"INTERNET"}
