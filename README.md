# VanthinkMD3

基于 **NeLuaJ+** 的原生 Android 应用，是原 Web 版《Vanthink WebMDUI2》的完整重构版。
界面全部使用 Android 原生 View + Material Design 3 构建，**不使用 WebView 承载任何主要界面**，
不含 HTML / CSS / JavaScript 前端代码。

| 项目 | 说明 |
| --- | --- |
| 应用名称 | VanthinkMD3 |
| 包名 | `com.xiaolin.vanthink` |
| 开发语言 | Lua（LuaJ++ / Lua 5.4 语法扩展） |
| 运行环境 | NeLuaJ+ Runtime |
| UI 技术 | Android 原生 View + Material Components 3 |
| 网络 | OkHttp（运行时 `okhttp` 同步 / `okHttp` 异步 + `xTask` 协程调度） |
| 数据格式 | JSON（`json` 模块） |
| 本地存储 | Android Keystore(AES/GCM) + SharedPreferences |
| 最低系统 | Android 8.0（API 26） |

---

## 一、功能介绍

### 作业

- 作业列表：分页加载（每页 20 条）、下拉刷新、滚动到底自动加载、加载更多按钮兜底。
- 筛选：时间范围（全部 / 本周 / 上周 / 本月）、完成状态（全部 / 未完成 / 已完成），使用 MD3 Chip。
- 作业卡片：标题、班级、类型、布置时间、完成度进度环、练习项数量、状态徽标（未开始 / 进行中 / 已完成）。
- 作业详情：教师与班级信息、练习项列表、达标要求、排名入口、分享入口。
- 状态覆盖：加载中 / 空数据 / 网络错误（带重试）/ 分页结束提示。

### 练习与成绩

- 排行榜：按练习项查看班级排行（昵称、正确率、耗时），并显示自己是否已完成。
- 记录练习完成：单个练习的手动入口，由用户输入**真实练习耗时**后二次确认提交。
- 一键完成（作业详情页）：确认一次后自动处理该作业的全部练习，无需逐题填写或逐项确认。
- 批量操作（作业首页）：多选最多 **30 个**作业后统一自动执行，卡片显示选中态、支持全选与清空。

自动操作流程（`app/services/homework_batch.lua`）：

1. 自动获取选中作业的详情，汇总全部练习；
2. 自动跳过语音练习（名称含「读」但名称不等于「阅读理解」）；
3. 查询各练习排行榜，读取自己的完成状态（`self.is_answered` + `self.accuracy`）；
4. 已达到目标的练习自动跳过（达标模式 100、普通模式 80）；
5. 取**排行榜第 1 名的有效耗时**作为 `spend_time`，校验范围 1～86400 秒；
6. 串行调用 `submitCompletion()` 提交，单项失败不影响其他项；
7. 自动统计成功 / 失败 / 语音跳过 / 已完成跳过 / 无有效排行榜数据，并生成结果列表。

约束：

- 不使用随机数生成或偏移耗时，不添加伪装真人的等待；
- 第 1 名数据缺失、无效或接口异常时记录该项无法处理的原因，**不擅自生成耗时**；
- 请求超时/连接失败后先重新查询服务端状态再判定，避免把已落库的提交误报为失败；
- 支持取消尚未执行的队列项目，已发出的请求按其真实结果记账；
- `scores=0`、`correct_rate=0`、`wrong_exercises=[]` 严格沿用服务端 `saveScore` 的数据结构。

### 通知中心

- 通知列表（分页）、未读视觉区分、未读数量统计。
- 单条点击进入详情并自动标记已读；支持批量标记已读（仅提交当前已加载的未读项）。
- 下拉刷新与分页。

### 统计

- 摘要卡片：练习次数、答对题数、练习天数、拍照练习（含月均与指定月数值）。
- 布局响应式：宽屏两张卡片等分一行（固定 12dp 间距），窄屏（< 360dp）自动退化为单列。
- 柱状图（每日答对题数）、折线图（每日练习时长），**原生 Canvas 自绘**，无 WebView、无第三方图表库。
- 年月筛选、磨耳朵累计时长、加载与错误状态。

### 分享

- 调用官方接口获取服务端合成的作业分享图。
- 支持保存到系统相册（MediaStore）与调用 Android 系统分享面板。

### Auth 迁移

- 被传端：生成一次性二维码（**纯 Lua 实现 QR 编码器 + 原生 Canvas 渲染**）、状态轮询、复制链接。
- 接收端：粘贴二维码链接领取登录状态。
- 完整失败处理：已使用（HTTP 410）、不存在（404）、服务不可用、格式错误。

> 运行时不提供 zxing / MLKit / 任何二维码库（已实测 `com.google.zxing.*`、`com.journeyapps.*`、
> MLKit、CameraX 均不存在），因此**不集成摄像头扫码**，接收端采用粘贴链接方式。

### 主题

- 深浅色：跟随系统 / 浅色 / 深色，持久化。
- 动态取色：跟随壁纸（Material You）或自定义种子色；6 组预设色 + 自定义十六进制输入。
- 颜色角色统一从 `themeUtil` / 主题属性读取，页面不硬编码颜色。
- 主题切换后重建 Activity 使色板生效；启动路径不会触发无谓重建。

### 更新与关于

- 更新日志拉取与展示（新增 / 优化 / 修复 / 备注），发现新版本弹窗提示。
- 关于页、隐私与安全说明页。
- 更新服务不可用**不会**影响应用启动与任何主流程。

### 登录

- 独立设计的登录页（MD3 描边输入框、密码可见性切换、加载态按钮、字段级错误提示）。
- 登录失败保留已输入的手机号；成功后保存手机号用于下次预填（密码从不保存）。
- 扫码登录 / 迁移入口。

---

## 二、运行环境

| 项 | 要求 |
| --- | --- |
| 系统 | Android 8.0（API 26）及以上 |
| 运行时 | NeLuaJ+（本工程在 `71_20261113_1142` 上验证，Android 15 / API 35 设备） |
| 网络 | 需可访问 `https://api.wxzxzj.com`（业务数据） |
| 权限 | 仅 `INTERNET` |

可选（缺失不影响主功能）：

- `https://zxzjurl.930390.xyz` —— Auth 迁移（第三方中转）
- `https://zxzjverlog.930390.xyz` —— 更新日志（第三方）

---

## 三、安装方法

### 方式一：直接安装 APK

1. 获取打包产出的 APK（见下一节编译方法）。
2. 在 Android 设备上允许「安装未知来源应用」后安装。
3. 首次启动进入登录页。

### 方式二：在 NeLuaJ+ 中运行

1. 用 NeLuaJ+ 打开本工程根目录。
2. 运行 `main.lua`。

---

## 四、编译方法

1. 用 NeLuaJ+ 打开工程根目录（含 `init.lua` 的目录）。
2. 检查 `init.lua`（应用名、包名、版本、SDK、权限、主题）。
3. 使用 IDE 的**打包**功能，在打包器界面完成签名配置并导出 APK。
4. 构建产物默认位于 `/sdcard/LuaJ/Builds/`。

关键配置（`init.lua`）：

```lua
app_name = "VanthinkMD3"
package_name = "com.xiaolin.vanthink"
ver_name = "0.2.4"
ver_code = "204"
min_sdk = "26"
target_sdk = "33"
debug_mode = false
NeLuaJ_Theme = "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay"
user_permission = {"INTERNET"}
```

---

## 五、主题说明

| 设置项 | 可选值 | 存储键 |
| --- | --- | --- |
| 深浅色 | 跟随系统 / 浅色 / 深色 | `vt_pref_theme_mode` |
| 取色来源 | 跟随壁纸 / 自定义种子色 | `vt_pref_theme_seed_source` |
| 种子色 | 任意 `#RRGGBB` | `vt_pref_theme_seed` |

- 预设色沿用原项目的 6 组：`#BB1614` / `#9A25AE` / `#0061A4` / `#00681C` / `#695F00` / `#006874`。
- 动态取色通过 `activity.dynamicColor(seed)` 在 `setContentView` 之前应用。
- **Android 12 / 12L / 13 限制**：这些版本上 Material 库对种子色的覆盖机制缺失，会回退为跟随壁纸取色；色值仍会保存，升级系统后生效（界面已提示）。
- 修改深浅色时由 AppCompat 自动重建 Activity；修改种子色需重建一次才能生效。

---

## 六、UI 布局约定

本项目所有视图都由 `loadlayout` 动态创建，`LayoutParams` 由控件自身决定，因此有以下硬性约定：

- **带 weight 的视图必须在加入父容器前显式调用 `kit.applyLinearParams()`**。
  独立 `loadlayout` 出来的根视图（`FrameLayout`、`MaterialCardView` 等）拿到的是
  `FrameLayout.LayoutParams`，**没有 weight 字段**，
  用 `layout_width = "0dp"` + `layout_weight = N` 会得到宽度 0 的不可见视图。
  `kit.listItem` / `kit.pageHeader` / `kit.sectionTitle` / `kit.card` / `kit.column(weight = …)` 已内部处理，
  自定义布局时需要自己调用。
- **横向 LinearLayout 内的间距用 `kit.hSpacer(widthDp)`，纵向用 `kit.spacer(heightDp)`**。
  `spacer` 的宽度是 `match_parent`，放进横向行会吃掉整行剩余宽度，把后面的控件挤出屏幕。
- **外边距必须在加入父容器前写进 `LayoutParams`（用 `kit.applyMargins()`）**。
  `loadlayout` 根视图拿到的是 `android.view.ViewGroup$LayoutParams`，该类型**没有边距字段**，
  写在 spec 里的 `layout_margin*` 会被静默丢弃。实机实测：`kit.card(..., { marginHorizontal = 16 })`
  加入竖向 LinearLayout 后 `leftMargin` 仍为 0，卡片直接贴屏幕边缘。
  `kit.card` / `kit.listItem` / `kit.group` / `kit.sectionTitle` / `kit.text` / `kit.row` / `kit.column`
  已内部处理；自行创建的 View 需要显式调用。
- **边距参数一律按 dp 解释**（`marginHorizontal = 16` 即 16dp）。

统一间距规范集中在 `kit.SPACING`，页面一律从这里取值，不再写魔法数字：

| 键 | 值(dp) | 用途 |
| --- | --- | --- |
| `pageHorizontal` | 16 | 页面左右视觉基线：卡片边缘、列表项图标左缘、分组标题、页头标题共用 |
| `sectionTop` | 20 | 分组标题上间距 |
| `sectionBottom` | 8 | 分组标题下间距 |
| `cardGap` | 12 | 卡片与卡片之间（含统计页双列 / 双行的行列间距） |
| `groupGap` | 10 | 分组卡片之间 |
| `cardPadding` | 16 | 卡片内部 padding（不在卡片内重复叠加外边距） |
| `pageBottom` | 16 | 页面底部余量 |
| `listIcon` | 24 | 列表项 Leading Icon 容器与图标尺寸 |
| `listIconGap` | 16 | 图标与文字间距（正文列落在 56dp MD3 keyline） |

`kit.listItem` 采用 MD3 Leading Icon 布局：图标容器 24dp、图标 24dp、图标后间距 16dp、行内水平 padding 16dp；
单行最小高度 56dp、双行 72dp（用 `setMinimumHeight`，内容更多时自然撑开），整行仍是点击区域并带原生 Ripple。
标题最多 2 行、副标题最多 3 行，右侧箭头固定宽度不参与挤压。

### MD3 转场动画

动画统一由 `app/ui/motion.lua` 管理，页面内不写动画代码：

| 场景 | 转场 | 时长 |
| --- | --- | --- |
| 顶级页面切换（作业 / 通知 / 统计 / 我的） | `MaterialFadeThrough` | 280ms |
| 二级页进入 | `MaterialSharedAxis` X，`forward = true` | 300ms |
| 二级页返回 | `MaterialSharedAxis` X，`forward = false` | 300ms |

- 三个 Material 类在 Runtime 中实测均可用（见 `_probe_transition.txt`）；任一缺失时自动降级为
  `ViewPropertyAnimator` 的淡入 + 小幅位移/缩放，不会因缺少动画类崩溃。
- 同一容器同时只允许一个转场：新转场先 `TransitionManager.endTransitions()` 结束旧的，
  再在同一帧内交换视图，快速连点导航不会出现视图叠加。
- 遵循系统「动画时长缩放」，`animator_duration_scale` 为 0 时直接切换；首屏与 `{ instant = true }` 不播动画。
- 动画不出现在网络回调与列表刷新路径中。

### 图标

`app/ui/icons.lua` 用 `Path` + `Canvas` 在 24×24 逻辑网格上自绘，缓存为 `BitmapDrawable`，
无字体、无外部图片。底部导航区分两套状态：选中为填充版（`assignment` / `notifications` /
`insights` / `person`），未选中为描边版（`assignment_outline` / `notifications_outline` /
`insights_outline` / `person_outline`）；切换由 `shell.applyTabIcons()` 在选中项变化时替换
菜单图标完成，Indicator 与选中动画仍由 `BottomNavigationView` 原生逻辑负责。

二级页统一用 `router.subPage({ title = ..., content = <View> })` 创建外壳，
`content` 会被挂载到返回栏下方的内容区并自动铺满（`setContent(view)` / `setContent(nil)` 可热替换与清空）。

UI 回归诊断：运行 `tools/ui_regression.lua` 会真实测量各页面的 View 尺寸并输出
`_ui_regression.txt`（不访问网络，服务层使用桩数据）。当前版本结果：**PASS 182 / FAIL 0**。

---

## 七、已知限制

1. **未用真实账号验证完整业务流程**。开发环境没有有效学生账号，因此登录成功后的作业列表、通知、统计等数据链路只验证了「接口可达 + 鉴权生效 + 错误码解析」以及桩数据下的 UI 尺寸断言，未验证真实数据渲染。详见 `docs/TEST_REPORT.md`。
2. **不支持摄像头扫码**。运行时无可用二维码解码库；Auth 迁移接收端改为粘贴链接。
3. **语音练习未实现**。原项目该功能本身不可用（脚本从未加载、依赖 3 个非官方服务、存在字段级 bug），本版本仅保留业务识别与提示，未引入录音 / ASR / OSS 依赖。详见 `docs/UNIMPLEMENTED.md`。
4. **批量自动操作要求排行榜存在第 1 名记录**。完全没有人完成过的练习没有可用参考耗时，
   会被记为「无有效耗时」并跳过，不做默认值补位。
5. **Auth 迁移与更新日志依赖第三方域名**，可用性不受本应用控制；这两项均为可选能力。
6. **登录态失效依赖服务端返回 `errcode: 44`**，没有 refresh token 机制（官方接口未提供），失效后需重新登录。
7. 深色模式首次切换会重建 Activity（Material 主题机制决定），属预期行为。
8. 无平板 / 横屏专属布局，大屏下为单列拉伸。窄屏（< 360dp）时统计页摘要卡片退化为单列，其他位置仍按可用宽度自适应。
9. **深色模式下的文字对比度断言未复跑**：回归脚本只在当前系统模式下检查，需在真机切换深色后复跑一次。

---

## 八、目录结构

```
VanthinkMD3/
├── init.lua                  打包与应用配置
├── main.lua                  入口：主题 → 外壳 → 登录态判断
├── app/
│   ├── config.lua            接口地址、分页与筛选常量、主题预设
│   ├── state.lua             登录态、账号缓存、未读数
│   ├── router.lua            底部导航与二级页压栈
│   ├── services/             auth / homework / homework_batch / notice / statistics / share / update / transfer / http
│   ├── storage/              secure（Keystore 加密）/ preferences（SharedPreferences）
│   ├── ui/
│   │   ├── theme.lua         颜色角色、单位、深浅色、种子色
│   │   ├── icons.lua         Path 自绘图标（缓存为 BitmapDrawable，含导航填充/描边双态）
│   │   ├── kit.lua           MD3 基础构件（文字/卡片/按钮/列表项/状态块/滚动页）+ SPACING 规范
│   │   ├── motion.lua        Material Motion 转场（FadeThrough / SharedAxis + 降级动画）
│   │   ├── chart.lua         Canvas 图表（柱状/折线/进度环/二维码渲染）
│   │   ├── dialogs.lua       Material 对话框与 Snackbar
│   │   ├── shell.lua         登录页 ↔ 主界面切换、Insets、返回键
│   │   └── pages/            login / homework / homework_detail / homework_batch / practice
│   │                         notifications / statistics / profile / theme_settings
│   │                         changelog / about / security / transfer
│   └── utils/                formatter / validator / logger / qrcode
├── res/string/               字符串资源（app_title）
├── docs/                     交付文档
├── tools/                    开发期验证脚本（不参与运行，不随打包产物发布）
│   ├── ui_regression.lua     UI 回归诊断：真实测量 View，含 v0.2.3 图标/边距/转场断言
│   └── test_batch_v024.lua   v0.2.4 批量操作检查：耗时解析 / 完成判定 / 批量引擎 / 多选上限 / 文案
└── html/                     原 Web 版源码（仅作迁移参考，不参与构建）
```

---

## 九、文档索引

| 文档 | 内容 |
| --- | --- |
| `docs/API.md` | 接口清单：URL、方法、参数、鉴权、返回结构、调用位置 |
| `docs/ARCHITECTURE.md` | 分层架构、渲染策略、异步模型、关键设计决策 |
| `docs/MIGRATION.md` | 原项目功能迁移对照表、合规性修改说明 |
| `docs/SECURITY_AUDIT.md` | 安全审计：凭据存储、第三方风险、原项目遗留问题 |
| `docs/TEST_REPORT.md` | 测试与验收报告索引（v0.2.2 基线 + v0.2.4 批量操作结论） |
| `docs/FIX_REPORT_v0.2.2.md` | v0.2.2 UI 渲染与布局修复记录（中文根因分析与改动清单） |
| `docs/FIX_REPORT_v0.2.3.md` | v0.2.3 UI 精修与 Material Motion 变更日志 + UI 回归结果 + 动画类兼容性检查 |
| `docs/BATCH_REPORT_v0.2.4.md` | v0.2.4 自动操作恢复说明、批量操作测试报告（PASS 85 / FAIL 0）与关于页修订说明 |
| `docs/UNIMPLEMENTED.md` | 暂未实现功能清单与后续扩展方案 |
| `docs/LEGACY_ANALYSIS.md` | 原 Web 项目源码分析（重构依据） |
