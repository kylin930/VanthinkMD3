# API 接口清单

所有接口均基于原 Web 项目**实际在用的调用**整理，并已通过线上请求实测确认可达性与鉴权行为。
未编写任何推测的接口。

- 官方业务接口：`https://api.wxzxzj.com`（9 个）
- 第三方可选服务：`*.930390.xyz`（3 个）
- 鉴权方式：请求头 `Authorization: <token>`（**裸 token，无 `Bearer` 前缀**）

集中定义位置：`app/config.lua` 的 `M.API` 与 `M.THIRD_PARTY`。Service 层不得再硬编码 URL。

---

## 0. 通用约定

### 鉴权

```
Authorization: <token>
```

- 未登录时 Service 层**直接返回本地错误**，不发出必然失败的请求（`app/services/http.lua`）。
- 鉴权失败统一表现为 HTTP 200 + 业务错误码：

```json
{ "errcode": 44, "errstr": "\u9a8c\u8bc1\u5931\u8d25" }
```

`errcode 44` 已在真机实测确认（无 token / 错误 token 访问 `/api/userinfo/getAccount`、
`/api/homework/student/getHomeworkList`、`/api/common/share/commonShare` 均返回该结构）。

### 业务错误码

| errcode | 含义 | 实测来源 |
| --- | --- | --- |
| `0` | 成功 | 全部接口 |
| `44` | 验证失败（鉴权无效） | `/api/userinfo/getAccount` 等 |
| `108` | 手机号未注册 | `/api/auth/student/login` |

### 请求体格式（受运行时能力限制）

运行时 `okhttp` 模块的能力边界已实测：

| 方法 | 可用性 | 说明 |
| --- | --- | --- |
| `okhttp.get(url, headers)` | 可用 | `headers` 为 Lua table |
| `okhttp.post(url, formTable, headers)` | 可用 | **表单体用 Lua table 传入**，运行时自动编码为 `application/x-www-form-urlencoded` |
| `okhttp.postJson(url, jsonString, headers)` | 可用 | 传字符串，运行时置 `application/json` |
| 字符串表单体 | **不可用** | `okhttp.post(url, "a=1&b=2")` 抛 `bad argument: table expected, got string` |

因此**不支持 `multipart/form-data`**。原项目用 `FormData` 提交的登录与通知列表接口，
已实测改用表单体 / JSON 体后服务端正常解析（返回业务错误码而非格式错误），见各接口说明。

---

## 1. 登录

```
POST https://api.wxzxzj.com/api/auth/student/login
鉴权：无
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `phone` | string | 手机号 |
| `password` | string | 密码 |

返回：

```json
{ "data": { "token": "...", ... } }
```

- 成功判定：`data.token` 为非空字符串。
- 实测：`phone=10000000000` 返回 `{"errcode":108,"errstr":"手机号未注册，请先注册"}`，
  证明参数名与请求体格式正确。
- 代码：`app/services/auth.lua` `M.login`

---

## 2. 当前账号信息

```
GET https://api.wxzxzj.com/api/userinfo/getAccount
鉴权：Authorization
```

参数：无。

返回关键字段：

| 字段 | 含义 | 用途 |
| --- | --- | --- |
| `data.id` | 学生 ID | 统计接口入参、账号卡片展示 |
| `data.nickname` | 昵称 | 作业页副标题、我的页 |
| `data.head_url` | 头像 URL | 我的页头像 |
| `data.pendant_url` | 头像框 URL | 未使用（原项目用于装饰） |
| `data.vip_icon` | VIP 图标 URL | 未使用 |

- 代码：`app/services/auth.lua` `M.fetchAccount`
- 启动时用于校验登录态是否仍有效。

---

## 3. 作业列表

```
GET https://api.wxzxzj.com/api/homework/student/getHomeworkList
鉴权：Authorization
```

| 参数 | 类型 | 取值 |
| --- | --- | --- |
| `page` | number | 从 1 起 |
| `page_size` | number | 本应用固定 20（原项目 50） |
| `time` | string | `all` / `week` / `last_week` / `month` |
| `degree` | string | `all` / `done` / `undone` |

返回：

```json
{ "errcode": 0, "data": { "total": 123, "list": [ ... ] } }
```

`data.list[]` 实际使用字段：

| 字段 | 含义 |
| --- | --- |
| `id` | 作业 ID |
| `name` | 作业名 |
| `description` | 描述 |
| `created_at` | 布置时间（`YYYY-MM-DD HH:mm:ss`） |
| `completion_rate` | 完成率（0-100，兼容 0-1 比例） |
| `vanclass_name` | 班级名（缺失视为已退班） |
| `type.name` | 作业类型名 |
| `testbank_count` | 题数 |
| `status` / `is_history` / `is_public` / `forceDeleting` | 原项目读取但未参与本应用逻辑 |

分页结束判定：`#list < page_size` 或累计已加载 >= `total`。

- 代码：`app/services/homework.lua` `M.fetchList`

---

## 4. 作业详情

```
GET https://api.wxzxzj.com/api/homework/student/getHomeworkInfo
鉴权：Authorization
```

| 参数 | 类型 |
| --- | --- |
| `homework_id` | string |

返回关键字段：

| 字段 | 含义 |
| --- | --- |
| `data.id` | 作业 ID |
| `data.name` | 作业名 |
| `data.teacher_name` | 教师名 |
| `data.created_at` | 布置时间 |
| `data.vanclass.name` | 班级名 |
| `data.type.name` | 作业类型 |
| `data.testbanks[]` | 练习项数组 |

`data.testbanks[]` 字段：

| 字段 | 含义 | 业务判据 |
| --- | --- | --- |
| `id` | 练习项 ID | 排行榜 / 提交入参 |
| `name` | 练习项名称 | |
| `game.id` | 游戏类型 ID | `saveScore` 的 `game_id` |
| `game.name` | 游戏类型名 | 含「读」且 ≠「阅读理解」→ 语音类 |
| `standard` | 达标分（存在即达标模式） | UI 徽标 |
| `accuracy` | 准确率要求 | UI 展示 |
| `entity_list[]` | 仅微课使用 | 本版本未使用（无视频播放） |

- 代码：`app/services/homework.lua` `M.fetchDetail`

---

## 5. 练习排行榜

```
GET https://api.wxzxzj.com/api/homework/student/getTestbankRankList
鉴权：Authorization
```

| 参数 | 类型 |
| --- | --- |
| `homework_id` | string |
| `testbank_id` | string |

返回：

| 字段路径 | 含义 |
| --- | --- |
| `data.list[0].rank_list[]` | 排行榜数组 |
| `...rank_list[].account.nickname` | 昵称 |
| `...rank_list[].account.head_url` | 头像 |
| `...rank_list[].accuracy` | 正确率（%） |
| `...rank_list[].spend_time` | 耗时（`m:ss` / `mm:ss`） |
| `data.list[0].self.is_answered` | 自己是否已作答（1 = 是） |
| `data.list[0].self.accuracy` | 自己正确率 |

- 代码：`app/services/homework.lua` `M.fetchRankList`

---

## 6. 提交练习完成记录

```
POST https://api.wxzxzj.com/api/game/saveScore
鉴权：Authorization
请求体：application/x-www-form-urlencoded
```

| 字段 | 本应用取值 | 说明 |
| --- | --- | --- |
| `record_id` | `"0"` | 新增记录 |
| `game_id` | 练习项 `game.id` | |
| `homework_id` | 作业 ID | |
| `testbank_id` | 练习项 ID | |
| `start_time` | 当前时间 `YYYY-MM-DD HH:mm:ss` | |
| `end_time` | 当前时间 + 用户输入耗时 | 由 `java.util.Calendar` 计算 |
| `spend_time` | 用户输入耗时，格式 `HH:MM:SS` | **用户实际填写** |
| `wrong_exercises` | `"[]"` | 服务端要求的占位 |
| `scores` | `"0"` | 不伪造分数 |
| `stars` | `"0"` | 不伪造星级 |
| `correct_rate` | `"0"` | 不伪造准确率 |

成功判定：`errcode === 0`。

**与原项目的差异（合规性修正）**：原项目会用「排行榜第一名耗时 + 随机 1~5 秒」自动生成
`spend_time`，并配合随机等待伪装真人操作，用于批量代刷。本应用改为由用户输入真实耗时并二次确认。

- 代码：`app/services/homework.lua` `M.submitCompletion`

---

## 7. 通知列表

```
POST https://api.wxzxzj.com/api/notice/getNoticeList
鉴权：Authorization
请求体：application/x-www-form-urlencoded
```

| 字段 | 取值 |
| --- | --- |
| `type` | `notice`（固定） |
| `page` | 页码，从 1 起 |
| `page_size` | 本应用 20（原项目 50） |

返回：

| 字段 | 含义 |
| --- | --- |
| `data.count` | 总数 |
| `data.list[].id` | 通知 ID |
| `data.list[].content` | 正文（**列表即全文，无详情接口**） |
| `data.list[].created_at` | 时间 |
| `data.list[].has_read` | 是否已读（0 / 1） |
| `data.list[].sender.nickname` | 发送者（缺省「系统」） |
| `data.list[].sender.head_url` | 发送者头像 |

- 代码：`app/services/notice.lua` `M.fetchList`

---

## 8. 标记通知已读

```
POST https://api.wxzxzj.com/api/notice/student/doReadNotice
鉴权：Authorization
请求体：application/x-www-form-urlencoded
```

| 字段 | 取值 |
| --- | --- |
| `notice_id_array` | JSON 数组字符串，如 `[123,456]` |

成功判定：`errcode === 0`。

- 批量已读只提交**当前已加载列表中的未读项**。原项目 `noticeList` 全局数组翻页不清空，
  会把历次翻页的 id 一并提交，本版本已修正。
- 代码：`app/services/notice.lua` `M.markRead`

---

## 9. 学生使用统计

```
POST https://api.wxzxzj.com/api/vanclass/getVanclassStudentReport
鉴权：Authorization
请求体：application/json
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `student_id` | number | 来自 `getAccount` 的 `data.id` |
| `year` | number | 年份 |
| `month` | number | 月份 1-12 |

返回：

| 字段路径 | 含义 |
| --- | --- |
| `data.practice.count` / `.avg` / `.month_avg` | 总练习次数 / 月均 / 指定月 |
| `data.exercise.count` / `.avg` / `.month_avg` | 总答对题数 / 月均 / 指定月 |
| `data.time.count` / `.avg` / `.month_avg` | 练习天数 / 日均分钟 / 指定月日均 |
| `data.photo_homework.count` / `.avg` / `.month_avg` | 拍照练习 |
| `data.pl_data.start_time` / `.total_time` / `.avg_time` | 磨耳朵起始日 / 累计分钟 / 日均分钟 |
| `data.list[].day` / `.score` / `.time` | 每日明细（日期 / 答对题数 / 分钟） |
| `data.student_name` | 学生名（未渲染） |

图表数据来源：柱状图取 `list[].score`，折线图取 `list[].time`。

- 代码：`app/services/statistics.lua` `M.fetchReport`

---

## 10. 分享图片

```
GET https://api.wxzxzj.com/api/common/share/commonShare
鉴权：Authorization
```

| 参数 | 取值 |
| --- | --- |
| `share_id` | 作业 ID |
| `share_type` | `homework_student`（固定） |

返回：

```json
{ "data": { "share_image": "https://..." } }
```

- 图片由**服务端合成**，前端只下载展示。原项目同样不做本地合成。
- 本应用额外实现：保存到相册（MediaStore）、系统分享面板。
- 代码：`app/services/share.lua`

---

## 11. Auth 迁移 —— 生成二维码

```
GET https://zxzjurl.930390.xyz/create?auth=<token>
鉴权：query 参数 auth
```

实测返回：

```json
{ "id": "a0bcjhy5qu", "url": "https://zxzjurl.930390.xyz/a0bcjhy5qu" }
```

- 二维码内容 = 返回的 `url` 本身（不是自定义 JSON）。
- 代码：`app/services/transfer.lua` `M.create`

---

## 12. Auth 迁移 —— 查询二维码状态

```
GET https://zxzjurl.930390.xyz/status/<code>
```

`code` = `url` 的最后一段。

实测返回：`{ "used": false }`；被领取后 `used` 变为 `true`。

- 应用每 3 秒轮询一次，`used === true` 时停止并提示。
- 代码：`app/services/transfer.lua` `M.checkStatus`

---

## 13. Auth 迁移 —— 领取登录状态

```
GET https://zxzjurl.930390.xyz/<code>
```

实测返回：`{ "auth": "<token>" }`；重复领取返回 **HTTP 410** `{"error":"Already used"}`。

| HTTP 状态 | 应用提示 |
| --- | --- |
| 200 + `auth` | 保存 Token 并刷新账号 |
| 410 | 该二维码已被使用（一次性有效） |
| 404 | 该二维码不存在或已过期 |
| 其他 | 领取失败，链接可能已失效 |

- 代码：`app/services/transfer.lua` `M.receive`

---

## 14. 更新日志

```
GET https://zxzjverlog.930390.xyz/api/version
鉴权：无
```

实测返回（截断）：

```json
{
  "version": "v3.2.0 Beta",
  "update_time": "目前已是最新版（2026/8/2）",
  "added": ["..."],
  "improved": ["..."],
  "fixed": ["..."],
  "note": "..."
}
```

- 版本判定沿用原项目逻辑：与本地已确认版本不同即视为新版本（不做语义化比较）。
- 服务不可用时只提示，**不影响启动与任何主流程**。
- 代码：`app/services/update.lua`

---

## 接口调用位置汇总

| 接口 | Service | UI 调用点 |
| --- | --- | --- |
| 登录 | `services/auth.lua` | `ui/pages/login.lua` |
| 账号信息 | `services/auth.lua` | `ui/shell.lua`、`pages/profile.lua`、`pages/statistics.lua` |
| 作业列表 | `services/homework.lua` | `pages/homework.lua` |
| 作业详情 | `services/homework.lua` | `pages/homework_detail.lua` |
| 排行榜 | `services/homework.lua` | `pages/practice.lua` |
| 提交完成 | `services/homework.lua` | `pages/practice.lua` |
| 通知列表 | `services/notice.lua` | `pages/notifications.lua` |
| 标记已读 | `services/notice.lua` | `pages/notifications.lua` |
| 统计报表 | `services/statistics.lua` | `pages/statistics.lua` |
| 分享图片 | `services/share.lua` | `pages/homework_detail.lua` |
| 迁移生成 | `services/transfer.lua` | `pages/transfer.lua` |
| 迁移状态 | `services/transfer.lua` | `pages/transfer.lua` |
| 迁移领取 | `services/transfer.lua` | `pages/transfer.lua`、`pages/login.lua` |
| 更新日志 | `services/update.lua` | `shell.lua`、`pages/changelog.lua`、`pages/profile.lua` |
