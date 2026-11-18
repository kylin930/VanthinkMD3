# 项目架构说明

## 一、分层结构

```
┌─────────────────────────────────────────────────────────┐
│  main.lua        入口：主题 → 外壳 → 登录态路由            │
├─────────────────────────────────────────────────────────┤
│  ui/      表现层   shell / router / pages / kit / chart   │
│                    theme / icons / dialogs                │
├─────────────────────────────────────────────────────────┤
│  services/ 业务层  auth / homework / notice / statistics   │
│                    share / update / transfer / http        │
├─────────────────────────────────────────────────────────┤
│  storage/ 存储层   secure(Keystore) / preferences          │
│  utils/   工具层   formatter / validator / logger / qrcode │
├─────────────────────────────────────────────────────────┤
│  config.lua  常量    state.lua  运行状态                   │
└─────────────────────────────────────────────────────────┘
```

依赖方向严格单向：`ui → services → storage/utils`，反向无引用。
业务层不 import 任何 UI 模块，UI 层不直接调用 `okhttp`。

---

## 二、各层职责

### 1. config（`app/config.lua`）

集中管理所有常量：

- 官方接口地址 `M.API`、第三方服务 `M.THIRD_PARTY`
- 分页大小、筛选选项（`TIME_FILTERS` / `DEGREE_FILTERS`）
- 业务错误码（`ERRCODE`）
- 主题预设色（`SEED_PRESETS`）、主题模式枚举

**规则**：Service 层不得硬编码 URL，一律引用 `config`。

### 2. storage

| 模块 | 用途 | 实现 |
| --- | --- | --- |
| `preferences.lua` | 非敏感偏好 | `activity.getSharedData/setSharedData`，键前缀 `vt_pref_` |
| `secure.lua` | 敏感数据（Token） | AndroidKeyStore AES/GCM，密文存于 SharedPreferences |

`secure.lua` 实现说明：运行时**不提供** `androidx.security.crypto.EncryptedSharedPreferences`
（已实测类不存在），因此用 `KeyStore("AndroidKeyStore")` + `KeyGenerator("AES")` +
`Cipher("AES/GCM/NoPadding")` 自建等价能力。密钥由系统 TEE 保管，不出设备。
密文格式：`v1:<base64(iv)>:<base64(ciphertext)>`。

### 3. utils

| 模块 | 职责 | 关键点 |
| --- | --- | --- |
| `logger.lua` | 日志 | 写 `android.util.Log`。**不用 `print`** —— 运行时 `print` 会产生界面提示，高频调用会遮挡界面并造成闪烁。输出前正则遮蔽长度 ≥24 的连续串（token 特征）。 |
| `formatter.lua` | 时间/数字格式化 | 自行实现日期解析与日差计算（不依赖 SimpleDateFormat 的时区行为）；`friendlyTime` 输出「今天 14:05 / 昨天 / N 天前」。 |
| `validator.lua` | 输入校验 | 手机号、颜色 `#RRGGBB` ↔ int 互转。 |
| `qrcode.lua` | QR 编码器 | 纯 Lua 实现，见下节。 |

### 4. services

| 模块 | 职责 |
| --- | --- |
| `http.lua` | **唯一**网络出口：URL 编码、鉴权注入、JSON 解析、错误分类、异步调度 |
| `auth.lua` | 登录、账号信息、退出 |
| `homework.lua` | 列表、详情、排行榜、提交完成、练习项类型判定 |
| `notice.lua` | 通知列表、标记已读、未读判定 |
| `statistics.lua` | 统计报表获取与字段归一化 |
| `share.lua` | 分享图获取、下载、保存相册、系统分享 |
| `update.lua` | 版本信息获取与「是否新版本」判定 |
| `transfer.lua` | Auth 迁移：生成、状态轮询、领取 |

**统一返回约定**：所有 Service 方法签名为 `fn(args..., callback(ok, dataOrMessage, rawResult))`，
`ok` 为布尔，失败时 `dataOrMessage` 是可读中文错误，`rawResult` 保留 `kind` / `errcode` / `httpCode`
供调用方判断（例如 `kind == "auth"` 触发重新登录）。

### 5. ui

| 模块 | 职责 |
| --- | --- |
| `theme.lua` | 颜色角色解析、dp/sp 换算、颜色符号归一化、深浅色、种子色 |
| `icons.lua` | 用 `android.graphics.Path` 在 24×24 网格绘制图标，缓存为 `BitmapDrawable` |
| `kit.lua` | MD3 基础构件工厂（text / card / button / listItem / stateView / scrollPage / group …） |
| `chart.lua` | Canvas 自绘：柱状图、折线图、进度环、二维码渲染 |
| `dialogs.lua` | MaterialAlertDialogBuilder 封装、Snackbar、对话框生命周期追踪 |
| `router.lua` | 底部导航四主页 + 二级页压栈（`push` / `back` / `reset`） |
| `shell.lua` | 登录页 ↔ 主界面切换、系统 Insets、返回键、认证失效统一处理 |
| `pages/*` | 具体页面 |

---

## 三、关键设计决策

### 1. 异步模型：`xTask` + 主线程回调

```lua
xTask {
  dispatcher = "io",
  task = function() ... okhttp.get(...) ... end,   -- 后台线程，可安全做同步 IO
  callback = function(result) ... 更新 UI ... end,  -- 主线程
}
```

- 运行时禁止主线程网络：实测同步 `okhttp` 在主线程抛 `NetworkOnMainThreadException`，
  在 `xTask` 的 io 调度器内正常。
- 所有 UI 更新都在 `callback` 中执行。
- 请求返回可取消 job（`job.cancel()`），Activity 销毁时自动取消。

### 2. HTTP 层的错误归一

`execute()` 把底层异常归类为 `kind`：

| kind | 触发条件 | 用户提示 |
| --- | --- | --- |
| `dns` | `UnknownHost` | 无法解析服务器地址，请检查网络 |
| `timeout` | `SocketTimeout` | 请求超时，请稍后重试 |
| `tls` | `SSL` / `CertPathValidator` | 安全连接失败 |
| `connect` | `ConnectException` | 网络连接失败 |
| `http` | 非 2xx | 服务器返回状态码 N |
| `auth` | `errcode == 44` | 触发重新登录 |
| `api` | 其他非 0 errcode | 透传服务端 `errstr` |

**绝不**在失败时返回伪造数据。

### 3. 渲染策略：外壳固定 + 区域重建

早期实现每次刷新都 `clear()` 整个 `ScrollView` 再重建，导致：

- 整屏重绘 → 视觉闪烁
- 滚动位置丢失
- 筛选 Chip 重建 → 每次重建都重新触发一次属性设置

现策略（`pages/homework.lua`、`pages/notifications.lua`）：

```
ScrollView
├── 页头（只建一次）
├── 摘要卡（只建一次，值通过 setText 更新）
├── 筛选栏（只建一次，选中态通过 setChecked 同步）
└── body 容器（内容变化时 removeAllViews + 重建）
```

`page.renderBody()` 只重建 `body`，`page.syncFilter()` 只更新 Chip 选中态。

### 4. 防重复加载

- `page.loading` 标志：请求进行中直接返回。
- 滚动分页只在「距底部 < 200dp **且** scrollY/内容高度发生变化」时触发，
  避免内容重排后反复触发分页（会导致连续请求与闪烁）。
- 认证失效处理 `authHandled` 一次性标志：多个并发请求同时返回 44 时只提示一次。

### 5. 颜色值符号问题（重要）

Lua 中 `0xFF0061A4` 是**无符号正整数** 4278215076，而 Java `int` 为 32 位有符号。
直接传给 `Paint.setColor(long)` / `setBackgroundColor` 会抛
`IllegalArgumentException: Invalid ID`。

因此 `theme.lua` 提供：

```lua
theme.normalize(color)  -- 无符号 → 有符号 int（传给 Java 前必须调用）
theme.unsigned(color)   -- 有符号 → 无符号（持久化 / 十六进制展示）
```

所有自定义绘制（icons / chart / GradientDrawable）都经过 `normalize`。

### 6. 深浅色模式不触发无谓重建

`AppCompatDelegate.getDefaultNightMode()` 初值是 `MODE_NIGHT_UNSPECIFIED(-100)`。
若无条件调用 `setDefaultNightMode(FOLLOW_SYSTEM)`，AppCompat 会判定「值变化」
并重建已注册 Activity —— 这正是**启动瞬间整屏闪烁**的根因。

`theme.applyMode` 现在的判定：

```lua
if 目标 == FOLLOW_SYSTEM and (当前 == FOLLOW_SYSTEM 或 当前 == UNSPECIFIED) then
  return false   -- 不做任何调用
end
if 当前 == 目标 then return false end
setDefaultNightMode(目标)
```

交互中切换深浅色时**不再**额外调用 `recreate()`，由 AppCompat 自动重建一次。

### 7. 二维码：纯 Lua 编码器

运行时没有 zxing / MLKit / CameraX / 任何二维码库（逐一实测 `bindClass` 均失败）。
因此 `app/utils/qrcode.lua` 按 ISO/IEC 18004 自行实现：

- GF(256) 有限域（本原多项式 `0x11D`）
- Reed-Solomon 纠错（纠错等级 M，版本 1~10）
- 数据分块与交织
- 掩码 0~7 全评估 + 四条惩罚规则打分，选最优掩码
- 格式信息 BCH(15,5)（生成多项式 `0x537`，异或 `0x5412`）
- 版本信息 BCH(18,6)（版本 ≥ 7）

正确性通过独立解码器交叉验证，见 `docs/TEST_REPORT.md`。

### 8. 图标：Path 自绘

运行时 `res.drawable(name)` 仅能命中极少量内置图标（实测 56 个 Material 图标名中仅 7 个可用：
`save/settings/info/search/add/close/menu_book`）。因此 `ui/icons.lua` 用
`android.graphics.Path` 在 24×24 逻辑网格上绘制约 40 个图标（支持填充与描边两种模式），
按 `(名称, 尺寸, 颜色)` 缓存为 `BitmapDrawable`。

### 9. 图表：Canvas 自绘

`ui/chart.lua` 用 `Bitmap + Canvas` 绘制后设给 `ImageView`：

- 柱状图：圆角柱、Y 轴 4 条网格线、X 轴标签最多抽样 7 个
- 折线图：面积渐变填充（alpha 36）、圆点（点数 ≤31 时）
- 进度环：`drawArc`，完成度 100% 时切换为 tertiary 色
- 空数据：居中显示「暂无数据」

### 10. Insets 与返回键

- `shell.init()` 通过 `ViewCompat.setOnApplyWindowInsetsListener` 读取 systemBars 内边距，
  避免内容被状态栏/导航栏遮挡。
- 返回键通过 `activity.addOnBackPressedCallback` **只注册一次**：
  栈内有二级页 → `router.back()`；在非首页 → 回作业首页；否则 `finish()`。

---

## 四、状态管理

`app/state.lua` 维护：

| 字段 | 说明 | 持久化 |
| --- | --- | --- |
| `token` | 登录凭据 | 仅 `secure`（Keystore 加密） |
| `account` | 账号展示信息 | 偏好设置（非敏感） |
| `unreadCount` | 未读通知数 | 否（运行时） |

提供 `subscribe(fn)` 事件订阅（`token` / `account` / `unread` 事件），当前页面按需订阅。

`state.bootstrap()` 在启动时恢复 Token 与账号缓存。

---

## 五、扩展指引

| 需求 | 改动点 |
| --- | --- |
| 新增接口 | `config.lua` 加地址 → `services/xxx.lua` 实现 → 页面调用 |
| 新增页面 | `ui/pages/xxx.lua` 返回 `{ key, view, onShow?, onHide? }` → `router.push(...)` |
| 新增底部导航项 | `ui/shell.lua` 的 `TAB_ITEMS` + `router.registerTab` |
| 新增图标 | `ui/icons.lua` 的 `ICONS` 表加 Path 定义 |
| 新增主题色预设 | `config.lua` 的 `SEED_PRESETS` |
| 调整颜色角色 | `ui/theme.lua` 的 `M.colors()` |
