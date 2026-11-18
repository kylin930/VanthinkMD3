# Vanthink WebMDUI2（html/ 旧版 Web 客户端）技术分析

分析对象：`/storage/emulated/0/LuaJ/Projects/VanthinkMD3/html` 全部源码（不含 `server.py`，`jsQR.js` / `qrcode.min.js` 仅看调用方式）。
所有结论均来自源码，行号对应当前文件内容。

---

## 0. 技术栈与加载顺序（先决事实）

| 事实 | 依据 |
| --- | --- |
| 纯静态单页：`index.html` + 16 个本地 JS 文件（其中 `doReadGame.js` 被注释、未加载） | `index.html:17-18,320-337` |
| UI 框架 MDUI 2（CDN，unpkg），图标字体 Google Material Icons | `index.html:11-12`, `index.html:41` |
| 阿里云 OSS Web SDK 6.17.1（CDN，全局 `OSS`） | `index.html:16` |
| `jsQR.js`（摄像头解码）与 `qr.js`（本项目二维码封装）异步加载 | `index.html:17-18` |
| 彩蛋模块以 ESM 方式 `import`（含 gsap CDN 依赖） | `index.html:334-337`, `destructiveEasterEgg.js:2` |
| 语音练习 `doReadGame.js` **已被注释掉，未加载**（关键结论，见第 10 节） | `index.html:322` |
| 业务分片按 `tY4mX2gU → uF4aI7iR → pV9zI6mU → 1737esdt → gN2xY5qQ → mG4bU8tP → md3-chart → stats → ciallo` 顺序同步加载 | `index.html:325-333` |
| 线上标题：`Vanthink WebMDUI2`；关于页版本号为静态文本 `v3.0.0 Release` | `index.html:9,221,296`, `index.html:128` |
| `qrcode.min.js` 文件存在但 **未在 index.html 中被引用**（导致二维码实际不可用，见第 3 节） | 全目录搜索 `qrcode.min.js` 仅命中文件名本身，`index.html` 无 `<script src="qrcode.min.js">` |

各 JS 分片职责：

| 文件 | 职责 |
| --- | --- |
| `index_tY4mX2gU.js` | Auth 存取、`fetchWithAuth`/`postWithAuth`、学生信息渲染、账号密码登录、登录态检查、退出登录 |
| `index_uF4aI7iR.js` | 作业详情渲染、单题提交分数、排行榜、一键完成、多选批量执行 |
| `index_pV9zI6mU.js` | 作业列表加载/分页/筛选、错误提示、Ciallo 音效监听、启动登录检查 |
| `index_1737esdt.js` | 页面切换（page1 ↔ page2）与返回 |
| `index_gN2xY5qQ.js` | 作业分享图片 |
| `index_mG4bU8tP.js` | 通知中心（列表/单条已读/本页已读/分页） |
| `stats.js` | 使用统计（取账号 ID、取报表、渲染卡片+图表） |
| `md3-chart.js` | 纯 SVG 柱状图/折线图/统计卡片渲染器 |
| `qr.js` | 二维码生成封装 + jsQR 摄像头扫描封装 + 扫码状态轮询 |
| `trans.js` | Auth 迁移 UI（生成端/接收端/扫码登录） |
| `getUpdateLog.js` | 更新日志获取与展示 |
| `ColorPickerMD2.js` | 主题色（预设/自选/壁纸取色/记忆） |
| `UIThemeModeMD2.js` | 深/浅色模式切换 |
| `ciallo.js` | 本地音效（Web Audio） |
| `destructiveEasterEgg.js` | 点击彩蛋（粒子爆炸） |

---

## 1. API 清单

### 1.1 总览

- **官方接口（`https://api.wxzxzj.com`）共 10 个**。
- **第三方/自建代理接口（`*.930390.xyz`）共 7 个**。
- 另有 1 处 **OSS SDK 直传**（`OSS.put`，非 HTTP 接口清单内，见 1.13）。
- **鉴权方式统一为请求头 `Authorization: <token>`（裸 token，无 `Bearer ` 前缀）**，由 `fetchWithAuth` 注入（`index_tY4mX2gU.js:18-30`）。第三方代理接口则把 token 放在 **query/表单字段 `auth`** 里。

| # | 接口 | 方法 | 鉴权 | 位置 |
| --- | --- | --- | --- | --- |
| 1 | `https://api.wxzxzj.com/api/auth/student/login` | POST(multipart) | 无 | `index_tY4mX2gU.js:92` |
| 2 | `https://api.wxzxzj.com/api/userinfo/getAccount` | GET | Authorization | `index_tY4mX2gU.js:61`, `stats.js:7`, `index.html:68` |
| 3 | `https://api.wxzxzj.com/api/homework/student/getHomeworkList` | GET | Authorization | `index_pV9zI6mU.js:1,21,170` |
| 4 | `https://api.wxzxzj.com/api/homework/student/getHomeworkInfo` | GET | Authorization | `index_uF4aI7iR.js:13,374` |
| 5 | `https://api.wxzxzj.com/api/homework/student/getTestbankRankList` | GET | Authorization | `index_uF4aI7iR.js:137,203,483` |
| 6 | `https://api.wxzxzj.com/api/game/saveScore` | POST(form-urlencoded) | Authorization | `index_uF4aI7iR.js:74` |
| 7 | `https://api.wxzxzj.com/api/common/share/commonShare` | GET | Authorization | `index_gN2xY5qQ.js:3` |
| 8 | `https://api.wxzxzj.com/api/notice/getNoticeList` | POST(multipart) | Authorization | `index_mG4bU8tP.js:65` |
| 9 | `https://api.wxzxzj.com/api/notice/student/doReadNotice` | POST(form-urlencoded) | Authorization | `index_mG4bU8tP.js:19,43` |
| 10 | `https://api.wxzxzj.com/api/vanclass/getVanclassStudentReport` | POST(JSON) | Authorization | `stats.js:28` |
| 11 | `https://zxzjurl.930390.xyz/create` | GET | query `auth` | `trans.js:44` |
| 12 | `https://zxzjurl.930390.xyz/status/{code}` | GET | 无 | `qr.js:63` |
| 13 | `https://zxzjverlog.930390.xyz/api/version` | GET | 无 | `getUpdateLog.js:45` |
| 14 | `https://zxzjapi.930390.xyz:2778/api/tool/upload/getStsToken` | GET | query `auth` | `doReadGame.js:193,204` |
| 15 | `https://zxzjapi.930390.xyz:2778/api/game/getTestbankDetail_mobileV2` | GET | query `auth` | `doReadGame.js:664` |
| 16 | `https://zxzjapi.930390.xyz:2778/api/common/saveSpokenScore` | POST(form-urlencoded) | 表单字段 `auth` | `doReadGame.js:581` |
| 17 | `https://awasr.930390.xyz/asr` | GET | 无 | `doReadGame.js:6` |

> 说明：`930390.xyz` 系列不是官方域名，是原作者的第三方中转/扩展服务。业务数据仍来自官方 `api.wxzxzj.com`。

### 1.2 登录 `POST /api/auth/student/login`

- 位置：`index_tY4mX2gU.js:87-126`（`getToken()`）。
- 请求体：`FormData`（即 `multipart/form-data`），显式 `method: "POST"`，**不带任何鉴权头**（`index_tY4mX2gU.js:88-96`）。

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `phone` | string | 手机号，取 `#phone` 输入框（`index_tY4mX2gU.js:89`） |
| `password` | string | 密码明文，取 `#pass` 输入框（`index_tY4mX2gU.js:90`） |

- 返回：`{ data: { token: string, ... } }`，成功判定为 `data.data.token` 真值（`index_tY4mX2gU.js:100-102`）。
- 失败处理：无 token → 弹「账号或密码输入错了喵」；HTTP 异常 → 弹错误并继续 `loadData()`（`index_tY4mX2gU.js:111-125`）。
- 调用位置：登录对话框按钮 `#subLogin`（`index_tY4mX2gU.js:139-141`）。

### 1.3 当前账号 `GET /api/userinfo/getAccount`

- 位置：`index_tY4mX2gU.js:59-85`（`renderStudentInfo`）、`stats.js:4-16`（取 `data.id`）、`index.html:48-68`（连通性探测）。
- 参数：无（鉴权头携带 token）。
- 返回关键字段：

| 字段路径 | 含义 | 使用处 |
| --- | --- | --- |
| `data.id` | 学生 ID | `index_tY4mX2gU.js:77`, `stats.js:10` |
| `data.nickname` | 昵称 | `index_tY4mX2gU.js:76` |
| `data.head_url` | 头像 URL | `index_tY4mX2gU.js:73` |
| `data.pendant_url` | 头像框（背景图）URL | `index_tY4mX2gU.js:72` |
| `data.vip_icon` | VIP 图标 URL | `index_tY4mX2gU.js:75` |

- 请求头：`Authorization`（`fetchWithAuth`）。
- 附加用途：`index.html:50` 用 `fetch(url,{method:'GET',cache:'no-cache'})` 测延迟，然后 `mdui.snackbar` 提示「连接延迟: X ms，…喵」（`index.html:48-66`）；此调用未带鉴权头，仅用于测速。

### 1.4 作业列表 `GET /api/homework/student/getHomeworkList`

- 位置：`index_pV9zI6mU.js:1`（常量）、`:21`（首屏）、`:170`（加载更多）。

| 参数 | 类型 | 含义 | 取值 |
| --- | --- | --- | --- |
| `page` | number | 页码，从 1 起 | `window.currentPage`（`index_pV9zI6mU.js:12,168`） |
| `page_size` | number | 每页条数 | 固定 50（`index_pV9zI6mU.js:13`） |
| `time` | string | 布置时间筛选 | `all` / `week` / `last_week` / `month`（按钮定义 `index.html:279-282`） |
| `degree` | string | 完成度筛选 | `all` / `done` / `undone`（按钮定义 `index.html:285-287`） |

- 返回：`{ errcode, errstr, data: { total, list: [...] } }`；`errcode !== 0` 视为失败（`index_pV9zI6mU.js:28-30`），总数取 `data.total || data.list.length`（`:40`）。
- `data.list[]` 使用到的字段（`index_pV9zI6mU.js:61-98`）：

| 字段 | 含义 | 备注 |
| --- | --- | --- |
| `id` | 作业 ID | 失败回落 `'N/A'` |
| `name` | 作业名 | |
| `description` | 描述 | |
| `created_at` | 布置时间（字符串，形如 `YYYY-MM-DD HH:mm:ss`，前端直接展示） | `index_pV9zI6mU.js:111` |
| `updated_at` | 更新时间 | |
| `completion_rate` | 完成率（0-100） | 用于圆形进度条 `:112-113` |
| `vanclass_name` | 班级名 | 缺失回落「已退班」 |
| `type.name` / `type.type_code` | 作业类型（如「普通模式」「达标模式」） | |
| `is_public` | 是否公开（1/0） | |
| `forceDeleting` | 强制删除标记 | |
| `is_history` | 是否历史（1/0） | |
| `status` | 状态（1 正常 / 其他停用） | |
| `entity_count` | 实体数 | |
| `testbank_count` | 题数 | 列表与多选对话框显示（`:111,295`） |
| `is_finish` | 完成人数（`parseInt`） | `:84,111` |

- 分页逻辑：`hasMoreData = list.length > 0 && allData.length < total`（`index_pV9zI6mU.js:183`）；「加载更多」按钮由脚本动态创建（`:228-234`），文案 `加载更多 (第 N 页)`（`:149`）。

### 1.5 作业详情 `GET /api/homework/student/getHomeworkInfo`

- 位置：`index_uF4aI7iR.js:13`（进入详情页）、`:374`（批量执行前预取）。
- 参数：`homework_id`（string，query）。
- 返回：`{ errcode, data: {...} }`，`renderInfo` 使用（`index_uF4aI7iR.js:80-101`）：

| 字段路径 | 含义 |
| --- | --- |
| `data.id` | 作业 ID（批量执行时用） |
| `data.name` | 作业名，写入顶部标题 `#appbar-title`（`:86`） |
| `data.teacher_name` | 老师名（`:88`） |
| `data.created_at` | 布置时间（`:88`） |
| `data.vanclass.name` | 班级名（`:88`） |
| `data.type.name` | 作业类型（`:88`） |
| `data.testbanks[]` | 练习项数组 |

`data.testbanks[]` 每一项（练习项）使用的字段（`index_uF4aI7iR.js:89-100`、`:643-654`）：

| 字段 | 含义 | 用途 |
| --- | --- | --- |
| `id` | 练习项（testbank）ID | 提交分数、排行榜、语音练习入参 |
| `name` | 练习项名称 | |
| `game.id` | 游戏类型 ID | `saveScore` 的 `game_id` |
| `game.name` | 游戏类型名 | **业务分支判据**：含「读」且不等于「阅读理解」= 语音类（`:180,382,512`）；`微课` 走视频分支（`:646`） |
| `game.icon` | 图标 URL | 列表头像 |
| `standard` | 达标分（存在即「达标模式」） | 判定 `isStandardMode`（`:383`），展示 `standard*100`（`:94`） |
| `accuracy` | 准确率要求 | 展示（`:94`） |
| `entity_list[]` | 实体列表（仅微课用） | `JSON.parse(entity.testbank_extra_value).video.video` 取视频地址（`:648-649`） |

### 1.6 提交/完成练习 `POST /api/game/saveScore`

- 位置：`index_uF4aI7iR.js:43-78`（`submitGameScore`），经 `postWithAuth` 以 `application/x-www-form-urlencoded` 发送（`index_tY4mX2gU.js:36-42`）。
- 请求体字段（`index_uF4aI7iR.js:60-71`）：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `record_id` | string | 固定 `'0'`（新增记录） |
| `game_id` | string | 游戏类型 ID（`item.game.id`） |
| `homework_id` | string | 作业 ID |
| `testbank_id` | string | 练习项 ID |
| `start_time` | string | `YYYY-MM-DD HH:MM:SS`（UTC，`toISOString` 截断，`:46`） |
| `end_time` | string | 开始时间 + 手工填入的耗时（`:47-50`） |
| `spend_time` | string | `HH:MM:SS`（`:52-58`） |
| `wrong_exercises` | string(JSON) | 固定 `'[]'` |
| `scores` | string | 固定 `'0'` |
| `stars` | string | 固定 `'0'` |
| `correct_rate` | string | 固定 `'0'` |

- 返回：`{ errcode, errstr, ... }`；成功判定 `errcode === 0`（`index_uF4aI7iR.js:237,552`）。
- 调用点：单题「提交分数」`saveScores`（`:103-129`，耗时来自动态生成的 `#spend-time` 输入框 `:657`）、一键完成（`:236`）、批量执行（`:551`）。
- UI 为**前端模拟**：`saveScores` 用随机步长播放「黑客破解服务器中🥴」进度条（`index_uF4aI7iR.js:107-115`），与真实请求进度无关。

### 1.7 排行榜 `GET /api/homework/student/getTestbankRankList`

- 位置：`index_uF4aI7iR.js:137`（手动查看）、`:203`（一键完成参考第一名）、`:483`（批量执行，兼做「已完成」判定）。
- 参数：`homework_id`、`testbank_id`（query）。
- 返回结构（`:144-152`、`:487-490`）：

| 字段路径 | 含义 |
| --- | --- |
| `data.list[0].rank_list[]` | 排行榜数组 |
| `...rank_list[].account.nickname` | 昵称 |
| `...rank_list[].account.head_url` | 头像 |
| `...rank_list[].accuracy` | 准确率（%） |
| `...rank_list[].spend_time` | 耗时（`m:ss` 或 `mm:ss`，经 `parseTimeToSeconds` 解析，`:33-41`） |
| `data.list[0].self.is_answered` | 自己是否已作答（1 = 是） |
| `data.list[0].self.accuracy` | 自己准确率，用于与通过阈值比较（`:488`） |

- 展示：弹窗 `#ranklist-dialog` + `#rankingList`（`index.html:73-77`）。

### 1.8 分享图片 `GET /api/common/share/commonShare`

- 位置：`index_gN2xY5qQ.js:1-33`（`getSharePic`）。
- 参数（query）：`share_id`（= `homeworkIdData`，即当前作业 ID）、`share_type`（固定 `homework_student`，`index_gN2xY5qQ.js:32`）。
- 返回：`{ data: { share_image: string } }` —— 服务器返回的**已合成图片 URL**（`:9`），前端只做 `<img>` 展示与全屏（`:14-20`）。
- 触发：详情页「炫耀一下」按钮 `#homeworkShare`（`index.html:309`）。

### 1.9 通知列表 `POST /api/notice/getNoticeList`

- 位置：`index_mG4bU8tP.js:57-85`（`loadNoticeList`）。
- 请求：**`FormData`（multipart/form-data）**（`:60-65`），`postWithAuth` 对 `FormData` 不覆盖 `Content-Type`（`index_tY4mX2gU.js:43-49` 只处理非 FormData 对象）。

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `type` | string | 固定 `'notice'`（`:61`） |
| `page` | string | 页码（`:62`） |
| `page_size` | string | 固定 50（`:4,63`） |

- 返回：`{ data: { list: [...], count: number } }`（`:70`）。
- `data.list[]` 字段（`:95-118`）：

| 字段 | 含义 |
| --- | --- |
| `id` | 通知 ID（已读请求用） |
| `content` | 正文（渲染前 `escapeHtml` 转义，`:105,128-136`） |
| `created_at` | 时间字符串，前端 `new Date(str.replace(' ','T'))` 转换成本地时间（`:97`） |
| `has_read` | 是否已读（`!has_read` 时加 `active` 高亮，`:99`） |
| `sender.nickname` | 发送者名（缺省「系统」，`:96`） |
| `sender.head_url` | 发送者头像（缺省显示 `person` 图标，`:98,101-103`） |

- 备注：**没有「通知详情」接口**，列表内容即全文；旧注释里曾存在的 GET 形式已被注释（`index_mG4bU8tP.js:66`）。

### 1.10 标记已读 `POST /api/notice/student/doReadNotice`

- 位置：`index_mG4bU8tP.js:6-33`（单条）、`:35-55`（本页批量）。
- 请求：`application/x-www-form-urlencoded`（`:15-21`）。

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `notice_id_array` | string(JSON 数组) | 单条为 `[id]`（`:16`）；批量为本页收集到的 `noticeList`（`:40`，在 `:107` 逐条 `push`） |

- 返回：代码未读取响应体，仅按成功与否更新 UI（单条成功后移除 `active`，`:23-24`）。
- 注意：`noticeList` 为全局数组（`:3`），翻页时**不会清空**，因此「已读本页」在多次翻页后会提交此前所有页的 id。

### 1.11 使用统计 `POST /api/vanclass/getVanclassStudentReport`

- 位置：`stats.js:25-37`（`fetchReport`），以 JSON 发送（`postWithAuth` 对普通对象 `JSON.stringify` 并置 `Content-Type: application/json`，`index_tY4mX2gU.js:43-49`）。

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `student_id` | number | 学生 ID，来自 `getAccount` 的 `data.id`（`stats.js:10,29`） |
| `year` | number | 年份（缺省当前年，`stats.js:182`） |
| `month` | number | 月份 1-12（缺省当前月，`stats.js:183`） |

- 返回结构（`stats.js:39-74`）：

| 字段路径 | 含义 |
| --- | --- |
| `data.practice.count` / `.avg` / `.month_avg` | 总练习次数 / 月均 / 指定月次数 |
| `data.exercise.count` / `.avg` / `.month_avg` | 总答对题数 / 月均 / 指定月 |
| `data.time.count` / `.avg` / `.month_avg` | 练习天数 / 日均分钟 / 指定月日均分钟 |
| `data.photo_homework.count` / `.avg` / `.month_avg` | 拍照练习总数 / 月均 / 指定月 |
| `data.pl_data.start_time` / `.total_time` / `.avg_time` | 「磨耳朵」起始日 / 累计分钟 / 日均分钟 |
| `data.list[]` | 每日明细：`day`（`YYYY-MM-DD`）、`score`、`time`（分钟） |
| `data.student_name` | 学生名（解析但未渲染） |

### 1.12 Auth 迁移/更新日志/语音三类第三方接口

见第 3、8、10 节（`zxzjurl.930390.xyz`、`zxzjverlog.930390.xyz`、`zxzjapi.930390.xyz:2778`、`awasr.930390.xyz`）。

### 1.13 OSS 直传（非 REST 清单内）

- 通过阿里云 OSS Web SDK `OSS.put(filename, blob)` 直传（`doReadGame.js:441`），bucket `vanthink`、region `oss-cn-qingdao`（`doReadGame.js:198-202`），凭证来自 `getStsToken`（第 10 节）。

---

## 2. 账号 / Auth 流程

### 2.1 存储与注入

| 环节 | 实现 | 位置 |
| --- | --- | --- |
| 存储 key | `localStorage['token']`（裸 token 字符串） | `index_tY4mX2gU.js:1-3` |
| 读 | `getAuth()` → `localStorage.getItem('token')` | `index_tY4mX2gU.js:5-7` |
| 清 | `clearAuth()` → `removeItem('token')` | `index_tY4mX2gU.js:9-11` |
| 注入方式 | 每个受保护请求加 `Authorization: localStorage.getItem('token')`（**无 `Bearer` 前缀**） | `index_tY4mX2gU.js:18-23` |
| 便捷 POST | `postWithAuth`：`URLSearchParams` → `x-www-form-urlencoded`；普通对象 → `application/json`；`FormData` → 原样交浏览器 | `index_tY4mX2gU.js:32-57` |
| 未使用的残留 | `genUuidAuth()` 生成伪 UUID，**全项目无调用点** | `index_tY4mX2gU.js:13-16` |
| 第三方接口注入 | token 作为 query/表单字段 `auth`：`trans.js:44`、`doReadGame.js:193,204,578,664` | 同左 |

### 2.2 登录入口

- 启动时 `DOMContentLoaded → checkLogin()`（`index_pV9zI6mU.js:236-238`）。
- 无 token 时把登录表单**动态注入 `#dohw` 对话框**：手机号 `#phone`、密码 `#pass`（`type=password toggle-password`）、「扫码登录」`#authLogin`、「登录」`#subLogin`（`index_tY4mX2gU.js:128-147`）。
- 有 token 则直接 `loadData()` + `renderStudentInfo()`（`index_tY4mX2gU.js:148-151`）。
- 两种登录方式：
  1. 账号密码：`getToken()` → `POST /api/auth/student/login`（第 1.2 节）。
  2. 扫码：`chooseMode('login')` 进入扫码流程（第 3 节），成功后 `saveAuth(res.auth)`。

### 2.3 token 失效 / 刷新

- **没有任何失效检测或刷新机制**：`fetchWithAuth` 只在 `!response.ok` 时抛 `HTTP出错了喵！状态码是：N`（`index_tY4mX2gU.js:26-28`）并交给各调用方 `showError` 弹窗；全项目无 401 分支、无 refresh 接口、无 `errcode` 与登录态联动（搜索 `401` 仅命中 `jsQR.js` 的查表常量）。
- 结论：token 过期后表现为「所有请求报 HTTP 错误」，用户必须手动「退出登录」再重新登录。

### 2.4 退出登录

- 抽屉菜单 `#logout` → `clearAuth()` → `mdui.alert` 提示「已退出登录（清除Auth）」→ `onConfirm` 里 `window.location.reload()`（`index_tY4mX2gU.js:161-169`）。
- 无服务端登出接口调用。

---

## 3. Auth 二维码迁移 / 传输协议（`trans.js` + `qr.js`）

### 3.1 角色选择 UI

- 入口：顶栏 ⋮ 菜单「迁移Auth」`#trans-btn`（`index.html:271`）→ 打开 `#mode-dialog`（`trans.js:1-3`）。
- 三个模式：`sender`（我是被传端 = 生成二维码）、`receiver`（我是接收端 = 扫码）、`login`（扫码登录，由 `checkLogin` 调用 `chooseMode('login')`，`index_tY4mX2gU.js:142-146`）。

### 3.2 生成端（被传端）

```
createQr()（trans.js:43-47）
  GET https://zxzjurl.930390.xyz/create?auth=${localStorage.getItem('token')}
  → data.url
  → createQRCode(data.url, 'qr-code')（qr.js:15-103）
```

- 二维码内容 = **`/create` 返回的 `url` 字符串本身**，不是自定义 JSON（`trans.js:46`）。`qr.js` 中没有构造任何 JSON payload。
- `createQRCode` 内部用 `new QRCode(el, {width:150,height:150,colorDark:'#7b636b',colorLight:'transparent',correctLevel:M, text})`（`qr.js:37-50`）。
- **实际不可用**：`QRCode` 由 `qrcode.min.js` 提供，而该文件未在 `index.html` 引入；`qr.js:28-31` 检测到 `typeof QRCode !== 'function'` 会 `console.error` 并 `return`，因此既不渲染二维码，也不会进入轮询。
- 轮询逻辑（若 QRCode 存在）：
  - 轮询间隔 `3000ms`（`qr.js:55`）。
  - `encodedText = text.replace('https://zxzjurl.930390.xyz/','')`（`qr.js:56`）——即取 URL 尾部 code。
  - `GET https://zxzjurl.930390.xyz/status/{code}`（`qr.js:63`）。
  - 返回 JSON 中 `data.used === true` → 把二维码容器替换为 `<mdui-chip>二维码已被扫描了喵</mdui-chip>` 并**停止轮询**（`qr.js:77-80`）；非 2xx 或异常则继续下一轮（`:69-73,81-91`）。
  - 使用 `AbortController` + `beforeunload` 中止（`qr.js:57,97-102`）。
- 无超时/过期处理、无重试上限、关闭对话框也不会停止轮询（只有 `beforeunload` 中止）。

### 3.3 接收端（扫码）

```
startScanning()（trans.js:49-86）
  startQRScanner('preview-video', onSuccess, onError)（qr.js:114-183）
  → onSuccess(scannedURL)
      fetch(scannedURL) → r.json() → saveAuth(res.auth)   （trans.js:62-64）
      mdui.confirm「识别成功喵」→ 确认后 loadData() + renderStudentInfo()（trans.js:65-74）
```

- 扫描实现：`navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'}})` + 每帧 `drawImage` 到 canvas + `jsQR(imageData.data,w,h)`（`qr.js:141-173`），识别一次即 `stopScan()` 关摄像头（`qr.js:164-167`）。
- 协议要点（真实代码结论）：
  - 二维码里放的是**一次性授权 URL**；扫描端直接 `GET` 该 URL，返回 JSON，取字段 **`auth`** 作为 token（`trans.js:64`），写入 `localStorage['token']`。
  - 生成端只通过 `status/{code}` 观察 `used` 标志，不参与传值。
- 失败处理：摄像头不可用/被拒 → `onError` → `mdui.snackbar` + 状态文字「扫描失败喵」，按钮复位（`trans.js:79-84`, `qr.js:175-180`）。
- 安全隐患：生成端把用户 token 明文放进**第三方服务器**的 query（`trans.js:44`），且二维码 URL 本身可被任何拿到的人换取 token（一次性由服务端 `used` 控制）。

---

## 4. 作业系统

### 4.1 列表（分页/筛选）

见 1.4。筛选交互：两个 `mdui-segmented-button-group`（`#timefilter` `index.html:278-283`、`#degfilter` `index.html:284-288`），`change` 时重新 `loadData(time, degree)` 并给按钮加 `loading`/`disabled`，完成后在 `loadData` 内移除（`index_pV9zI6mU.js:31-36,242-264`）。

### 4.2 详情与练习项

见 1.5。详情页渲染：
- 顶部标题、描述卡片「这是 X 老师于 Y 布置给 “Z班” 的练习喵，类型。」（`index_uF4aI7iR.js:88`）。
- 每个练习项一行 `mdui-list-item`，描述「达标：`standard*100`分/`accuracy`」+ 头像（`:92-96`）。
- 页面切换 `switchPage('page2', index)` 用 `homeworkDataList[index]` 取作业 ID（`index_1737esdt.js:7-23`，`homeworkDataList` 是**数组**，在渲染列表时 `push(homework.id)`，`index_pV9zI6mU.js:115`）。

### 4.3 单题提交 / 完成练习

- 点击练习项（`#homework-list` 委托，`index_uF4aI7iR.js:636-679`）按 `game.name` 分支：
  1. `微课`：取 `entity_list` 中 `testbank_extra_value` 的 `video.video` 播放 `<video>`，输入「通关时间（秒）」，按钮调 `saveScores(game.id, homeworkId, item.id)`（`:646-654`）。
  2. 非语音 / `阅读理解`：输入通关秒数 + 「提交分数」+ 「排行榜」按钮（`:655-662`）。
  3. `单词跟读` / `口语跟读` / `口语看读`：调用 `doReadGame('c'+item.id, homeworkInfoData.id)`（`:663-664`）——**该函数未定义**（见第 10 节）。
  4. 其他语音类：`mdui.confirm` 警告后，`onCancel`（按钮「让我访问！」）才进入 `doReadGame`（`:665-673`）。
- 提交接口与字段见 1.6。`saveScores` 读 `#spend-time` 的原始字符串直接传入 `submitGameScore`（`:105`），后者用 `spend_time` 数值计算 `end_time` 与 `HH:MM:SS`（`:47-58`），即输入的是**秒**。

### 4.4 一键完成非口语作业（Beta）

`#homeworkOneDo` 点击（`index_uF4aI7iR.js:171-256`）：
1. 过滤语音题：保留 `!(game.name.includes('读') && game.name !== '阅读理解')`（`:179-183`）。
2. 逐题：先查排行榜取第一名耗时 `original`，加 **随机 +1~5 秒** 作为提交耗时；无人做过/请求失败则默认 `30 + random(1..5)`（`:203-231`）。
3. 调 `submitGameScore(item.game.id, homeworkInfoData.id, item.id, spendTime)`，`errcode===0` 计成功；每题间隔 `400ms`（`:236-246`）。
4. 结果汇总文本（`:251-255`）。执行期间禁用遮罩关闭：`dohw.removeAttribute('close-on-overlay-click')`（`:173`、结束 `:250`）。

### 4.5 多选批量执行（batch）

- 入口：⋮ 菜单「多选练习」`#homeworkBatchDo`（`index.html:272`）→ `index_uF4aI7iR.js:268-337`。
- 流程：
  1. `isMultiple = true`；`loadData("all","undone")` 只取未完成的作业（`:269-270`）；`window.allData` 空则报错退出（`:273-277`）。
  2. 展示最多 `min(allData.length, 100)` 个复选框（`:279`），标签 `名称（题数）- 班级`（`:295`）；支持全选，上限 `MAX_SELECT_COUNT = 30`（`:259`，提示「最多只能选择 30 个作业喵」`:330`）。
  3. `executeBatch(selectedIndices)`（`:339-627`）：
     - 第 1 步：逐个 `getHomeworkInfo` 展开成扁平任务列表 `{homework, item, isVoice, isStandardMode}`，`isVoice` 判定同上，`isStandardMode = item.standard != null`（`:381-390`），每次 `wait(200)`（`:395`）。
     - 第 2 步：拆分为 `autoTasks`（非语音）/`voiceTasks`（语音，仅统计展示）；全为语音则直接结束（`:408-430`）。
     - 第 3 步：注册 `beforeunload` 阻止用户离开（`:433-438`，结束 `:585` 移除）。
     - 第 4 步：逐题
       - 通过阈值：达标模式 `100`，普通模式 `80`（`:457`）。
       - 用排行榜 `self.is_answered === 1 && self.accuracy >= threshold` 判断「已完成」并跳过（`:487-509`）。
       - 语音题二次检测跳过（`:512-521`）。
       - 耗时算法：第一名耗时 + 随机 `1~5` 秒；无数据则 `30 + random`（`:524-543`）。
       - **模拟真人等待**：`randomWait()`，随机 `3000~6000ms`（`:260-266`, `:546`）。
       - 提交 `saveScore`，成功 `errcode===0`；失败按 `errstr` 记录（`:549-570`）。
       - 每步更新进度条与预计剩余时间（按历史平均耗时推算，`:449-455,459-474`）。
     - 第 5 步：结果面板统计（总数/成功/跳过已完成/跳过语音/未成功/总耗时 + 折叠明细）（`:599-626`）。
  4. `isMultiple = false` 复位（`:587`）。

---

## 5. 通知中心

- 入口：抽屉「通知消息」`#msglist`（`index.html:212`）→ `#message-list` 对话框（`index.html:182-189`）→ `loadNoticeList(1)`（`index_mG4bU8tP.js:155-159`）。
- 列表：`POST /api/notice/getNoticeList`（见 1.9）。
- 渲染：头像/图标 + headline=内容 + description=`发送者 · 时间`，未读加 `active`（`index_mG4bU8tP.js:95-125`）。
- 单条已读：点击列表项 `onclick="doReadNotice(id)"`（`:113`）→ `POST /api/notice/student/doReadNotice` with `notice_id_array=[id]`（见 1.10）。
- 批量已读：「已读本页」`#read-page`（`index.html:185`）→ `oneReadNotice()` 提交 `noticeList`（`index_mG4bU8tP.js:35-55`）后重新加载当前页。
- 分页：`page_size = 50`（`:4`），总页数 `ceil(count/50)`，`prev/next` 按钮禁用态与文案「第 N 页，共 M 页」（`:138-153`）。
- XSS 防护：内容与发送者名都过 `escapeHtml`（`:105-106,128-136`）——通知内容是唯一做了转义处理的外部文本。

---

## 6. 统计（`stats.js` + `md3-chart.js`）

- 入口：⋮ 菜单「使用统计」`#statsBtn`（`index.html:273`）、抽屉 `#statsNavBtn`（`index.html:213`）；两者都绑 `openStatsDialog`（`stats.js:226-242`）。
- 对话框 `#statsDialog`（`index.html:105-118`）含年份 `#statsYear`、月份 `#statsMonth`（`type=number`）、刷新按钮 `#statsRefreshBtn`、loading、内容容器 `#statsContent`。
- 打开时默认填入当前年月并立即加载（`stats.js:215-224`）；刷新按钮重新 `loadStats`（`:239-241`）。
- 数据源：先 `GET /api/userinfo/getAccount` 拿 `data.id`（`stats.js:4-16`，模块内缓存 `currentStudentId`），再 `POST /api/vanclass/getVanclassStudentReport`（1.11）。
- 渲染（`stats.js:83-174`）：
  - 5 张统计卡（`MD3Chart.statCards`）：总练习次数、总答对题数、练习天数、拍照练习、磨耳朵累计；副标题含月均与指定月值（`:93-124`）。
  - 柱状图：`data.list[].score`，标签由 `day` 转 `MM/DD`（`getDailyLabels` `:76-81`, 数据 `:129`, 图 `:136-143`）。
  - 折线图：`data.list[].time`（分钟），`showArea: true`（`:130,149-156`）。
  - 纯文本汇总（`:159-173`）。
- 失败：整体 catch 后渲染「加载统计数据失败了喵」+ 错误信息（`:201-209`）。
- `md3-chart.js` 实现细节：
  - 纯 SVG 手绘，`viewBox` 固定 `0 0 560 {height}`，`width:100%`（`:70-74`）。
  - 颜色取自 CSS 变量 `--mdui-color-primary` / `--mdui-color-secondary` / `--mdui-color-surface-variant`，回落到 `#6750a4` / `#625b71` / `#e7e0ec`（`:34-44`）。
  - X 轴标签抽样最多 8 个（`sampleLabels` `:18-32`）；Y 轴 4 条网格线；数值缩写 `k`/`w`（`formatNumber` `:12-16`）。
  - 柱状图圆角 `rx=4`（`:127-131`）；折线图面积填充 `fill-opacity 0.15`、线宽 2.5、点数 ≤31 时画圆点（`:218-249`）。
  - `statCards` 用 `md3-animate-in` 逐个 60ms 入场（`:253-291`，样式 `md3-chart.css:44-56`）。

---

## 7. 分享图片

- **原项目没有本地 canvas 生成分享图**：分享按钮「炫耀一下」（`index.html:309`）点击后仅调 `GET /api/common/share/commonShare?share_id=<作业ID>&share_type=homework_student`，展示服务端返回的 `data.data.share_image`（`index_gN2xY5qQ.js:1-33`）。
- 交互：先显示 loading 转圈，图片 400px 高，附「全屏」按钮；全屏后给 `#dohw` 加 `fullscreen` 属性并重新渲染纯图（`:8-20`）。
- 无 canvas / 无外部截图服务的前端依赖，图片合成 100% 在服务端完成。

---

## 8. 更新系统（`getUpdateLog.js`）

- 接口：`GET https://zxzjverlog.930390.xyz/api/version`（`getUpdateLog.js:45`），**无需鉴权**。
- 返回结构（`renderChangelog` 使用，`:1-41`）：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `version` | string | 版本标识 |
| `update_time` | string | 预计更新时间（缺省显示「未指定」） |
| `added[]` | string[] | 新增 |
| `improved[]` | string[] | 优化 |
| `fixed[]` | string[] | 修复 |
| `note` | string | 备注 |

- 版本比较逻辑（`:49-52`）：**只做字符串全等**——`localStorage['last_update_version'] === data.version` 则视为「无更新」直接 return；不做语义化版本比较，也不与页面内写死的 `v3.0.0 Release`（`index.html:128`）比对。
- 展示：`#update-dialog`，headline 手工打开时「更新日志」，自动检测时「已发现新版本喵」（`:60`）。
- 确认（`#acknowledge-btn`）：关闭对话框；非手动触发时写入 `localStorage['last_update_version'] = data.version` 并 `mdui.snackbar` 提示「你可以在“设置”中再次查看更新日志喵」（`:63-74`）。为防止监听叠加，先 `btn.replaceWith(btn.cloneNode(true))` 再绑一次（`:76-79`）。
- 触发：`DOMContentLoaded` 自动检测一次（`:93-94`）；「获取更新日志」`#verlog-btn`（`index.html:135`）手动打开（`:96-99`）。
- **没有下载/跳转逻辑**：不存在 APK 下载地址、商店跳转或 `window.open`。

---

## 9. 主题系统（`ColorPickerMD2.js` + `UIThemeModeMD2.js`）

### 9.1 深浅色

| 项 | 实现 | 位置 |
| --- | --- | --- |
| 存储 | `localStorage['dark']` = `'yes'` / `'no'`（默认 `'no'`） | `UIThemeModeMD2.js:2,31` |
| 应用 | `mdui.setTheme("dark")` / `mdui.setTheme("light")` | `UIThemeModeMD2.js:11,20` |
| 切换 | 顶栏 `#qh` 按钮，图标在 `nightlight` / `light_mode` 间切换 | `UIThemeModeMD2.js:6,14,25-33` |
| 判断当前主题 | `mdui.getTheme() == "dark"` 时才提示「已切换为浅色模式」 | `UIThemeModeMD2.js:15` |

- **不跟随系统**：全项目无 `matchMedia`（已全局搜索确认），只有手动开关。

### 9.2 主题色

- 应用方式：`mdui.setColorScheme(hex)`（`ColorPickerMD2.js:3`），hex 用 `/^#[0-9A-Fa-f]{3,6}$/` 校验（`:2`）。
- 预设色（HTML `data-color`，`index.html:232-237`，与 `ColorPickerMD2.css:15-32` 的色块一致）：

| 名称 | 色值 |
| --- | --- |
| red | `#bb1614` |
| purple | `#9a25ae` |
| blue | `#0061a4` |
| green | `#00681c` |
| yellow | `#695f00` |
| grey | `#006874` |

- 自选色：`localStorage['mdui_custom_colors_v1']` 存 JSON 数组，去重后 `unshift` 到头部，**最多保留 5 个**（`ColorPickerMD2.js:13-27`）。
- 壁纸取色：`<input type=file accept=image/*>` → `img.decode()` → `await mdui.getColorFromImage(img)` 取主色并应用（`:73-105`；ID/按钮在 `index.html:257-260`）。
- 记忆开关：`#rememberColorCheckbox`（`index.html:264`），勾选时把当前色写入 `localStorage['mdui_rem_color']` 且 `mdui_rem_enabled='true'`（`:6-10`）；启动时若开启且有色值则重新 `applyColor`（`:190-202`）。
- 相关 localStorage key 汇总：`mdui_rem_color`、`mdui_rem_enabled`、`mdui_custom_colors_v1`、`dark`。
- **已知缺陷（重构时需注意）**：`#colorPicker` 的 `input` 监听和 `#wallpaperInput` 的 `change` 监听都注册了两遍（`:69-71` 与 `:159-161`；`:73-105` 与 `:164-188`），一次操作会触发两次 `addCustomColor`/`applyColor`。`clearCustomColors()` 定义但未被使用（`:29-33`）。

### 9.3 CSS 变量

- 图表 CSS 自定义变量（`md3-chart.css:1-10`）：`--md3-chart-primary`、`--md3-chart-secondary`、`--md3-chart-tertiary`、`--md3-chart-surface`、`--md3-chart-surface-variant`、`--md3-chart-on-surface`、`--md3-chart-on-surface-variant`、`--md3-chart-radius`，全部 `var(--mdui-color-*, 兜底色)` 派生。
- 颜色选择器样式使用 MDUI 变量：`--mdui-color-outline`、`--mdui-color-on-surface-variant`、`--mdui-color-surface-variant`、`--mdui-shape-corner-extra-small`、`--mdui-typescale-title-small-*`（`ColorPickerMD2.css:11-12,54-55,70-81`）。
- JS 读取的 MDUI 变量：`--mdui-color-primary`、`--mdui-color-secondary`、`--mdui-color-surface-variant`（`md3-chart.js:34-44`），以及 `--mdui-color-error`、`--mdui-color-on-surface-variant`（`stats.js:203-206`）。

---

## 10. 语音练习 `doReadGame.js`

### 10.1 依赖链

| 依赖 | 说明 | 位置 |
| --- | --- | --- |
| 阿里云 OSS SDK（`OSS` 全局） | `index.html:16` 引入 6.17.1 | 使用 `doReadGame.js:197-213` |
| STS 临时凭证 | `GET https://zxzjapi.930390.xyz:2778/api/tool/upload/getStsToken?auth=<token>`；返回 `StatusCode`、`AccessKeyId`、`AccessKeySecret`、`SecurityToken`、`Expiration`；`StatusCode !== 200` 抛错 | `doReadGame.js:191-218` |
| OSS 位置 | `region: 'oss-cn-qingdao'`、`bucket: 'vanthink'`、支持 `refreshSTSToken` | `doReadGame.js:197-213` |
| 录音 | `navigator.mediaDevices.getUserMedia({audio:true})` + `MediaRecorder` + `AnalyserNode` 画波形 | `doReadGame.js:359-385`，波形 `:221-249` |
| ASR | `GET https://awasr.930390.xyz/asr?audio=<编码后的 OSS URL>`，返回 `{transcription:{text, words:[{word,...}]}}` | `doReadGame.js:1-34` |
| 题目接口（非官方域名） | `GET https://zxzjapi.930390.xyz:2778/api/game/getTestbankDetail_mobileV2?auth=&testbank_id=&homework_id=`，取 `data.exercises[]`，`item.WR` 或 `item` 作为题目体，`asr_tool` 缺省 `'shengtong'` | `doReadGame.js:664-676` |
| 评分提交（非官方域名） | `POST https://zxzjapi.930390.xyz:2778/api/common/saveSpokenScore`（form-urlencoded） | `doReadGame.js:560-595` |

`saveSpokenScore` 字段（`doReadGame.js:569-578`）：

| 字段 | 值/含义 |
| --- | --- |
| `game_id` | **硬编码 `'26'`** |
| `testbank_id` | 入参（注意调用方传的是 `'c'+item.id`，见 `index_uF4aI7iR.js:664`） |
| `start_time` / `end_time` | `YYYY-MM-DD HH:mm:ss`（本地时间 `toISOString` 截断） |
| `spend_time` | `00:MM:SS`（`:563-566`） |
| `resource_id` | **硬编码 `'14362982'`** |
| `record_id` | `'0'` |
| `exercises` | JSON 数组，每项 `{id, right_answer, score, phonics[], custom_answer(OSS mp3 url), is_wrong, is_select:1, asr_tool, check_record:"0,", is_mobile:0}`（`:526-538`） |
| `auth` | token |

### 10.2 评分算法

- `computePhonicsScores(originalText, asrWords)`：把 ASR 词清洗成纯字母串，与目标串做贪心字符对齐（允许跳过 ≤2 个 ASR 字符 = 满分 1.0；跳过后命中 0.7；否则 0.0），非字母字符直接 1.0（`doReadGame.js:36-125`）。
- 总分 = 字母评分均值 × 100 取整；`<60` 记 `is_wrong=1`（`:465-474`）。
- 历史遗留的「随机打分」代码已被整段注释（`Math.floor(Math.random()*21)+80`，`:412-414`）——属于**前端模拟**，现已禁用。

### 10.3 完成度与可用性结论

**结论：此功能在当前版本不可用，且不建议在不引入未验证依赖的前提下迁移。**

依据：
1. `doReadGame.js` **在 `index.html` 中被注释掉，从不加载**（`index.html:322`），但 `index_uF4aI7iR.js:664,671` 仍直接调用 `doReadGame(...)` → 点击语音题会抛 `ReferenceError: doReadGame is not defined`，页面无任何降级提示。
2. 强烈依赖**三个非官方第三方服务**：`zxzjapi.930390.xyz:2778`（STS 中转 + 题目详情 + 评分提交）、`awasr.930390.xyz`（Whisper ASR）、以及阿里云 OSS SDK（`index.html:16`，且 OSS 直传需 STS 有效期刷新）。这些地址既非官方 API，也无任何文档/可用性保障。
3. 代码本身还有明显缺陷（即使恢复加载也无法正常跑通）：
   - `playUserBtn` 读 `ex.userAudioBlob`（`:488`），但录音分支只设置了 `ex.audioBlob`（`:434`）→ 回放永远失效。
   - 提交时 `right_answer: ex.textContent`（`:528`）——`ex` 上只有 `word` 字段（`:291`），`textContent` 恒为 `undefined`。
   - `getTestbankDetail_mobileV2` 走第三方端口 2778，与官方 `api.wxzxzj.com` 的练习项 ID 语义是否一致未经验证；调用方还额外加了 `'c'` 前缀（`index_uF4aI7iR.js:664`）。
4. 若必须保留该能力，可迁移的**已在前端验证的部分**只有：录音（MediaRecorder）、波形绘制（canvas）、字符级对齐评分算法（`computePhonicsScores`，纯函数，无外部依赖）——这三块不依赖任何未验证服务，可独立复用。ASR 与提交必须替换为官方接口，但官方接口目前代码中**没有**对应实现（第 1 节 10 个官方接口里无语音评分接口）。

---

## 11. 敏感信息

**未发现任何硬编码的 token / 密码 / AccessKey / secret 明文。** 逐项列出与安全相关的实际发现：

| 类型 | 位置 | 说明（已掩码，仅记录类型） |
| --- | --- | --- |
| 无硬编码密钥 | — | 全库搜索 `accessKey` 仅命中 `doReadGame.js:199,200,207,208`，均为**运行时**从 `getStsToken` 响应对 `data.AccessKeyId/AccessKeySecret` 的**变量引用**，非字面量（形如 `data.AccessKey***`） |
| OSS 静态配置（非密钥） | `doReadGame.js:198,202` | `region: 'oss-cn-qingdao'`、`bucket: 'vanthink'` —— 桶名与区域硬编码 |
| 用户 token 外泄风险 | `trans.js:44` | 把 `localStorage['token']` 作为 query `auth=` 发给第三方 `zxzjurl.930390.xyz`（URL 会进入对方访问日志/Referer） |
| 用户 token 外泄风险 | `doReadGame.js:193,204,578,664` | token 同上，以 `auth` 参数/表单字段发给第三方 `zxzjapi.930390.xyz:2778` |
| 凭证下发端点 | `doReadGame.js:193` | STS 临时凭证由第三方服务中转下发（前端直接调用），等价于把 OSS 权限委派给第三方服务 |
| 硬编码业务常量（非密钥） | `doReadGame.js:570`（`game_id='26'`）、`doReadGame.js:575`（`resource_id='14362982'`） | 魔法值，重构应改为由接口返回 |
| 明文密码传输方式 | `index_tY4mX2gU.js:88-96` | 手机号+密码以 `FormData` POST 到官方 HTTPS 接口（无本地加密、无验证码流程） |
| token 存储 | `index_tY4mX2gU.js:2` | 明文存 `localStorage['token']`，无过期时间、无加密 |

---

## 12. 其他有效业务逻辑

### 12.1 彩蛋（`destructiveEasterEgg.js`）

- 由 `index.html:334-337` 以 ES module `import` 引入，依赖 `https://unpkg.com/gsap@3.12.5/index.js`（`destructiveEasterEgg.js:2`）。
- Level 1：**5 秒内点击 `#ver-btn` 5 次**（`:22-25,44-53`）→ 启用「双击任意元素爆炸」（`dblclick` 捕获阶段，`:59-62`）：目标元素 `gsap` 缩小淡出 + 生成 80~120 个粒子 + 白色闪光（`:64-89,97-154`），并触发震动 `[50,30,50]`（`:159-172`）。
- Level 2：**15 次全局点击 / 7 秒**（注释写 15 秒，实为 `TIME_WINDOW_L2 = 7000`，`:23`）→ `triggerLevel2Explosion()` **函数体为空，未实现**（`:92-94`）。
- 震动用 `navigator.vibrate`（`:160-171`），不支持则静默跳过。

### 12.2 音效

- `ciallo.js`：`fetch('ciallo.aac')` → `AudioContext.decodeAudioData` 缓存 `audioBuffer` → 点击 `#ciallo` 用 `createBufferSource` 播放（`ciallo.js:1-29`）；`audioCtx.state === 'suspended'` 时先 `resume()` 并放弃本次播放（`:16-19`）。
- `index_pV9zI6mU.js:214-226`：**同一个 `#ciallo` 元素又绑了第二个监听**，用 `new Audio('https://www.nekopara.uk/webfiles/ciallo.aac')` 播放远程音源，音量 0.7，结束后 `remove()`。
- 结果：点击一次会同时播放本地 aac 与远程 aac（重复/叠音）。重构时二选一。

### 12.3 本地缓存 key 汇总

| key | 值 | 位置 |
| --- | --- | --- |
| `token` | 鉴权 token 字符串 | `index_tY4mX2gU.js:2,6,10,21` |
| `dark` | `'yes'` / `'no'` | `UIThemeModeMD2.js:2,31` |
| `mdui_rem_color` | 记住的主题色 hex | `ColorPickerMD2.js:8,190` |
| `mdui_rem_enabled` | `'true'` / `'false'` | `ColorPickerMD2.js:9,191,197` |
| `mdui_custom_colors_v1` | 自选色 JSON 数组（≤5） | `ColorPickerMD2.js:13-17` |
| `last_update_version` | 已确认过的更新日志版本号 | `getUpdateLog.js:50,67` |

### 12.4 运行时全局状态

- `window.currentPage` / `window.pageSize` / `window.totalItems` / `window.allData` / `window.hasMoreData` / `window.isLoading`（`index_pV9zI6mU.js:12-16,159,168,182-183`）。
- `window.allData` 同时被「多选练习」复用（`index_uF4aI7iR.js:273,292,363`）。
- `isMultiple`：全局多选模式开关（`index_pV9zI6mU.js:5`，`index_uF4aI7iR.js:269,587`，`index_1737esdt.js:30`）。
- `homeworkDataList`：列表顺序 → 作业 ID 的映射数组（`index_pV9zI6mU.js:2,115,129`；`index_1737esdt.js:18`）。
- `homeworkInfoData` / `homeworkIdData`：当前打开的作业详情与 ID（`index_uF4aI7iR.js:1-2,7,82`；分享用到 `homeworkIdData`，`index_gN2xY5qQ.js:3`）。
- `window.__spokenExerciseInit`：语音模块重入标记（`doReadGame.js:624-626`）。

### 12.5 其它细节

- 首屏加载遮罩 `#JMload`（一个远程 GIF）在 `DOMContentLoaded` 时被 `display:none` 隐藏（`index.html:42-47`）。
- 页面转场：`page1` 从左侧滑入、`page2` 从右侧滑入，`transition 0.9s/0.7s cubic-bezier`（`index.css:66-101`）；返回按钮触发 `loadData()` 刷新列表再切页（`index_1737esdt.js:36-40`）。
- 练习详情页进入时禁用分享/一键完成按钮，加载完再恢复（`index_uF4aI7iR.js:11-12,24-25`）。
- `#dohw` 对话框 `closed` 时清空 HTML 并移除 `fullscreen`（`index_uF4aI7iR.js:681-684`）；语音对话框 `#doreadgame` 关闭时重建内部结构（`doReadGame.js:694-703`）。
- 免责声明对话框完整文案（`index.html:146-181`），「小林的小窝」外链 `https://www.xiaorin.com`（`index.html:143`）。
- 外部图片资源大量依赖 `https://teachermate.oss-cn-qingdao.aliyuncs.com/...`（装饰图：`index.html:94,121,209,306`、`index.css:186`、`index_uF4aI7iR.js:142,660`、`trans.js:16,17,28,94`）与 `chat-page.oss-cn-hangzhou.aliyuncs.com`（加载动画，`index.html:43`）——重构时都是外部硬依赖。
- `server.py` 已废弃，按要求未分析。

---

## 13. 重构风险清单（基于上述事实）

1. **语音练习链路整体不可用**：脚本未加载 + 三个第三方服务 + 已知字段 bug（第 10 节）。
2. **Auth 迁移依赖第三方中转**，且二维码生成因 `qrcode.min.js` 未引入而实际失效（第 3 节）。
3. **token 无失效/刷新机制**，过期即全面报错（第 2.3 节）。
4. **第三方域名收下用户 token**（`trans.js:44`、`doReadGame.js:193,664`），迁移时应彻底移除。
5. **批量自动做题逻辑内嵌业务规则**（阈值 100/80、+1~5 秒、3~6 秒随机等待、最多 30 个），属产品级行为，重构需明确是否保留。
6. 通知「已读本页」数组不清空、主题色监听重复注册、Ciallo 双音源重复播放等确定性缺陷（第 1.10、9.2、12.2 节）。
7. 大量依赖 CDN（unpkg mdui/gsap、Google Fonts、阿里 OSS SDK），离线或国内网络环境不可用。
