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
- 记录练习完成：由用户输入**真实练习耗时**后二次确认提交，提交前明确说明用途。

> 原 Web 版的「一键完成 / 多选批量执行」会用随机耗时伪造完成记录（第一名耗时 +1~5 秒随机偏移、
> 3~6 秒随机等待伪装真人）。该实现会污染他人可见的排行榜数据，**本版本不再提供**，
> 只保留合规的真实提交入口。详见 `docs/MIGRATION.md`。

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
ver_name = "0.2.2"
ver_code = "202"
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

本项目所有视图都由 `loadlayout` 动态创建，`LayoutParams` 由控件自身决定，因此有两条硬性约定：

- **带 weight 的视图必须在加入父容器前显式调用 `kit.applyLinearParams()`**。
  独立 `loadlayout` 出来的根视图（`FrameLayout`、`MaterialCardView` 等）拿到的是
  `FrameLayout.LayoutParams`，**没有 weight 字段**，
  用 `layout_width = "0dp"` + `layout_weight = N` 会得到宽度 0 的不可见视图。
  `kit.listItem` / `kit.pageHeader` / `kit.sectionTitle` / `kit.card` / `kit.column(weight = …)` 已内部处理，
  自定义布局时需要自己调用。
- **横向 LinearLayout 内的间距用 `kit.hSpacer(widthDp)`，纵向用 `kit.spacer(heightDp)`**。
  `spacer` 的宽度是 `match_parent`，放进横向行会吃掉整行剩余宽度，把后面的控件挤出屏幕。

二级页统一用 `router.subPage({ title = ..., content = <View> })` 创建外壳，
`content` 会被挂载到返回栏下方的内容区并自动铺满（`setContent(view)` / `setContent(nil)` 可热替换与清空）。

UI 回归诊断：运行 `tools/ui_regression.lua` 会真实测量各页面的 View 尺寸并输出
`_ui_regression.txt`（不访问网络，服务层使用桩数据）。当前版本结果：PASS 120 / FAIL 0。

---

## 七、已知限制

1. **未用真实账号验证完整业务流程**。开发环境没有有效学生账号，因此登录成功后的作业列表、通知、统计等数据链路只验证了「接口可达 + 鉴权生效 + 错误码解析」以及桩数据下的 UI 尺寸断言，未验证真实数据渲染。详见 `docs/TEST_REPORT.md`。
2. **不支持摄像头扫码**。运行时无可用二维码解码库；Auth 迁移接收端改为粘贴链接。
3. **语音练习未实现**。原项目该功能本身不可用（脚本从未加载、依赖 3 个非官方服务、存在字段级 bug），本版本仅保留业务识别与提示，未引入录音 / ASR / OSS 依赖。详见 `docs/UNIMPLEMENTED.md`。
4. **批量自动做题已移除**。原因见 `docs/MIGRATION.md` 的合规性说明。
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
│   ├── services/             auth / homework / notice / statistics / share / update / transfer / http
│   ├── storage/              secure（Keystore 加密）/ preferences（SharedPreferences）
│   ├── ui/
│   │   ├── theme.lua         颜色角色、单位、深浅色、种子色
│   │   ├── icons.lua         Path 自绘图标（缓存为 BitmapDrawable）
│   │   ├── kit.lua           MD3 基础构件（文字/卡片/按钮/列表项/状态块/滚动页）
│   │   ├── chart.lua         Canvas 图表（柱状/折线/进度环/二维码渲染）
│   │   ├── dialogs.lua       Material 对话框与 Snackbar
│   │   ├── shell.lua         登录页 ↔ 主界面切换、Insets、返回键
│   │   └── pages/            login / homework / homework_detail / practice / notifications
│   │                         statistics / profile / theme_settings / changelog / about
│   │                         security / transfer
│   └── utils/                formatter / validator / logger / qrcode
├── res/string/               字符串资源（app_title）
├── docs/                     交付文档
├── tools/                    开发期验证脚本（不参与运行，不随打包产物发布）
│   └── ui_regression.lua     UI 回归诊断：真实测量 View，检查二级页 / 列表项 / 统计页
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
| `docs/TEST_REPORT.md` | v0.2.2 测试与验收报告（实测尺寸证据与未验证项） |
| `docs/FIX_REPORT_v0.2.2.md` | v0.2.2 UI 渲染与布局修复记录（中文根因分析与改动清单） |
| `docs/UNIMPLEMENTED.md` | 暂未实现功能清单与后续扩展方案 |
| `docs/LEGACY_ANALYSIS.md` | 原 Web 项目源码分析（重构依据） |
