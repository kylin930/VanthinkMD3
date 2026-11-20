-- VanthinkMD3 全局配置：接口地址、分页与筛选常量、主题预设
-- 所有网络地址集中在此，Service 层不得再硬编码 URL。

local M = {}

-- 官方接口（业务数据）
M.API_BASE = "https://api.wxzxzj.com"

M.API = {
  login = M.API_BASE .. "/api/auth/student/login",
  account = M.API_BASE .. "/api/userinfo/getAccount",
  homeworkList = M.API_BASE .. "/api/homework/student/getHomeworkList",
  homeworkInfo = M.API_BASE .. "/api/homework/student/getHomeworkInfo",
  testbankRankList = M.API_BASE .. "/api/homework/student/getTestbankRankList",
  saveScore = M.API_BASE .. "/api/game/saveScore",
  shareImage = M.API_BASE .. "/api/common/share/commonShare",
  noticeList = M.API_BASE .. "/api/notice/getNoticeList",
  noticeRead = M.API_BASE .. "/api/notice/student/doReadNotice",
  studentReport = M.API_BASE .. "/api/vanclass/getVanclassStudentReport",
}

-- 第三方辅助服务（原项目沿用，非官方域名）。全部为可选能力，
-- 失败不得影响应用启动与主流程。
M.THIRD_PARTY = {
  authTransferCreate = "https://zxzjurl.930390.xyz/create",
  authTransferStatus = "https://zxzjurl.930390.xyz/status/",
  updateLog = "https://zxzjverlog.930390.xyz/api/version",
  sourceHost = "zxzjurl.930390.xyz",
}

M.PAGE_SIZE = 20
M.NOTICE_PAGE_SIZE = 20

-- 作业列表筛选（与原项目 index.html 中的分段按钮一致）
M.TIME_FILTERS = {
  { key = "all", label = "全部" },
  { key = "week", label = "本周" },
  { key = "last_week", label = "上周" },
  { key = "month", label = "本月" },
}

M.DEGREE_FILTERS = {
  { key = "all", label = "全部状态" },
  { key = "undone", label = "未完成" },
  { key = "done", label = "已完成" },
}

-- 服务端业务错误码（依据实际接口响应确认）
M.ERRCODE = {
  OK = 0,
  AUTH_INVALID = 44,
  PHONE_NOT_REGISTERED = 108,
}

-- 主题：预设种子色（对应原项目 ColorPickerMD2 的预设项，色值一致）
M.SEED_PRESETS = {
  { key = "red", label = "赤陶红", color = 0xFFBB1614 },
  { key = "purple", label = "紫罗兰", color = 0xFF9A25AE },
  { key = "blue", label = "瓷器蓝", color = 0xFF0061A4 },
  { key = "green", label = "苔原绿", color = 0xFF00681C },
  { key = "yellow", label = "琥珀黄", color = 0xFF695F00 },
  { key = "grey", label = "青灰", color = 0xFF006874 },
}

-- 深浅色模式
M.THEME_MODE = {
  SYSTEM = "system",
  LIGHT = "light",
  DARK = "dark",
}

M.APP_VERSION = "0.2.2"
M.APP_NAME = "VanthinkMD3"

-- 主题种子的可选方式：system（跟随壁纸，仅 Android 12+）、seed（自定义种子色）
M.SEED_SOURCE = {
  SYSTEM = "system",
  SEED = "seed",
}

return M
