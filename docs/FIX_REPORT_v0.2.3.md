# v0.2.3 UI 精修与 Material Motion 变更记录

| 项目 | 内容 |
| --- | --- |
| 仓库 | `kylin930/VanthinkMD3` |
| 起始版本 | v0.2.2 |
| 目标版本 | **v0.2.3**（`ver_name = "0.2.3"`、`ver_code = "203"`、`app/config.lua` 的 `APP_VERSION = "0.2.3"`） |
| 范围 | UI 精修 + 交互动效；**未改动**业务 API、数据模型、登录逻辑 |
| 真机环境 | Android 15（API 35），NeLuaJ+ Runtime `71_20261113_1142`，360dp 宽 / 480dpi（1080px） |

---

## 一、变更总览

| # | 项目 | 文件 | 结果 |
| --- | --- | --- | --- |
| 1 | 「我的」左侧图标列收敛为 MD3 Leading Icon | `app/ui/kit.lua` | 图标容器 40→24dp、图标 22→24dp、间距 16dp、正文列落在 56dp keyline |
| 2 | 修复卡片外边距不生效 | `app/ui/kit.lua` | 新增 `M.applyMargins()`，卡片/分组/列表真正获得 16dp 左右边距 |
| 3 | 建立统一间距规范 | `app/ui/kit.lua` + 全部页面 | 新增 `kit.SPACING`，各页面改为引用常量 |
| 4 | 统计页年份按钮裁切 | `app/ui/pages/statistics.lua` + `kit.button` | 按钮由固定 36dp 改为「最小高度 48dp + wrap」，字体放大也不裁切 |
| 5 | 统计页月份栏精简 | `app/ui/pages/statistics.lua` | 删除重复刷新按钮，改为「年份按钮 + 月份图标 + 年月 Badge」，整行居中 |
| 6 | 统计页卡片间距 | `app/ui/pages/statistics.lua` | 双列 12dp、双行 12dp，图表卡片左右 16dp + 内 padding 14dp |
| 7 | 底部导航填充/描边双态图标 | `app/ui/icons.lua`、`app/ui/shell.lua` | 新增 4 个描边图标，选中填充、未选中描边 |
| 8 | MD3 页面转场动画 | 新增 `app/ui/motion.lua`、`app/router.lua` | FadeThrough 280ms / SharedAxis X 300ms，含降级与并发保护 |
| 9 | 卡片与列表项 Ripple | `app/ui/kit.lua` | 新增 `M.ripple()`，列表项使用系统 `selectableItemBackground` |
| 10 | 全页面视觉精修 | 各页面 | 统一 pageHorizontal / cardGap / cardPadding，取消重复 padding |

---

## 二、根因与修复细节

### 2.1 卡片外边距为什么一直不生效（本轮核心）

**现象**：`kit.card(..., { marginHorizontal = 16 })` 写了很多处，实机上卡片仍然贴着屏幕边缘。

**根因（实机实测定位）**：`loadlayout` 单独创建出来的根视图，其 `LayoutParams` 类型是
`android.view.ViewGroup$LayoutParams`——这个类型**没有边距字段**。写在 spec 里的
`layout_marginStart` / `layout_marginTop` 会被静默丢弃，不报错、不生效。

诊断脚本 `tools/probe_margin.lua` 的实测输出（修复前）：

```
[card in vertical LinearLayout]
  LP class = android.widget.LinearLayout$LayoutParams
  left margin = 0px
  top margin = 0px
  measured = 1080x153
  left/top/right/bottom = 0,0,1080,153
  expect left = 48px, width = 984px      ← 实际 0px / 1080px
```

`tools/probe_margin2.lua` 进一步确认：`layout_marginTop = "24dp"` 的根视图加入 LinearLayout 后
`topMargin = 0`、`getTop() = 0`，边距完全没有写进去。

同时发现第二个问题：`kit.applyLinearParams()` 把裸数字当**像素**处理
（`params.setMargins(sizeToPx(16), ...)`），即使边距能生效，`marginHorizontal = 16` 实际只有 5.3dp。

**修复**：
1. 新增 `M.applyMargins(view, opts)`：读取现有 `LayoutParams` 的 width/height/weight，
   构造 `LinearLayout.LayoutParams` 并写入四条边距，再 `setLayoutParams`。
   `column` / `row` / `scrollPage` / `card` 内部的父容器都是 `LinearLayout`，
   `addView` 会复用这份参数，边距与 weight 同时保留。
2. `kit.card` 无论有没有 `weight` 都走参数写入（原来只有 `weight` 分支才调用 `applyLinearParams`）。
3. 新增 `marginToPx()`：边距数字一律按 dp 解释；`sizeToPx()` 仍按像素处理 width/height，职责分离。
4. 顺带修复 `kit.text` / `kit.divider` / `kit.row` / `kit.column` / `kit.button` 的同类问题。

**修复后实测**（`tools/ui_regression.lua`）：

```
PASS  卡片左右外边距真正生效（不再贴屏幕边缘）
PASS  账号卡片左边缘为 16dp  [48px]
PASS  所有统计卡片左右边距 ≥ 12dp（图表不贴屏幕边缘）
PASS  双列卡片之间间距为 12dp  [36px]
PASS  两行摘要卡片之间间距为 12dp  [36px]
```

**父容器兼容性**：`LinearLayout.LayoutParams` 放进 `FrameLayout` 不会崩（`probe_margin3.txt` 已验证），
但为避免语义混乱，`applyMargins` 只用于 LinearLayout 体系内部；`router.attachView()` 仍显式设置
`FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)`，二级页正文铺满不受影响。

### 2.2 「我的」页面图标列

| 项 | v0.2.2 | v0.2.3 |
| --- | --- | --- |
| 图标容器 | 40×40dp | **24×24dp** |
| 图标本身 | 22dp | **24dp** |
| 图标后间距 | 16dp | 16dp（不变） |
| 行内水平 padding | 16dp | 16dp（不变） |
| 正文列左边缘 | 72dp | **56dp**（MD3 列表 keyline） |
| 标题 / 副标题 | 14sp / 12sp | **15sp / 13sp** |
| 行高 | 由 padding 决定 | 单行 ≥56dp、双行 ≥72dp（`setMinimumHeight`，内容多时自然撑开） |

- 整行仍是点击区域：padding 与最小高度都作用在整行容器上，缩小图标容器**不会**缩小触控区。
  回归实测双行列表项 `height = 238px`（≈79dp）且 `isClickable() && hasOnClickListeners()` 为 true。
- 标题最多 2 行、副标题最多 3 行；右侧箭头 / trailing 固定宽度并带 8dp 起始间距，
  文字容器 `weight = 1` 先让出空间，长文本不会挤压箭头（实测右侧箭头 72px 完整可见）。
- `SectionTitle` 左基线统一到 `pageHorizontal = 16dp`，与卡片边缘、列表图标左缘对齐。

### 2.3 统一间距规范

`kit.SPACING`（页面一律引用，不再写字面量）：

```lua
M.SPACING = {
  pageHorizontal = 16,  -- 卡片边缘 / 列表图标左缘 / 分组标题 / 页头标题共用
  sectionTop = 20,      -- 分组标题上间距
  sectionBottom = 8,    -- 分组标题下间距
  cardGap = 12,         -- 卡片之间（含统计双列、双行）
  groupGap = 10,        -- 分组卡片之间
  cardPadding = 16,     -- 卡片内部 padding
  pageBottom = 16,      -- 页面底部余量
  listIcon = 24,        -- 列表项图标容器与图标
  listIconGap = 16,     -- 图标与文字间距
}
```

层级区分（**不叠加**）：
- 页面与卡片之间：`pageHorizontal` + `cardGap` / `groupGap`
- 卡片与卡片之间：`cardGap`（列表）/ `groupGap`（分组）
- 卡片内部：`cardPadding`，卡片内不再加 margin
- 分组标题与分组卡片：`sectionTop` + `sectionBottom`

应用到的页面：作业列表、作业详情、通知列表、通知详情、统计中心、我的、主题设置、
关于、隐私与安全、更新日志、Auth 迁移、登录页（登录页保持 24dp 内容 padding）。

具体到「我的」：账号卡片与下方分组之间用 `spacer(4)` + `sectionTitle` 的 20dp 上间距形成层次；
同组列表项仍在一张卡片内用 `MaterialDivider` 分隔（回归实测 4 条分割线），
分组卡片之间 `groupGap = 10dp`（实测 133~163px）。

### 2.4 统计页年份按钮裁切

**根因**：`height = "36dp"` 是固定高度。`MaterialButton` 自带 `insetTop` / `insetBottom`（各 6dp）
与上下 padding（各 14dp），36dp 高度下可用内容区仅剩 14dp，中文 + 数字混排的行高（约 19~22dp）
被上下裁切；字体放大 1.3 倍时更严重。

**修复**：
1. `kit.button` 改为 `layout_height = "wrap"` + `setMinimumHeight(48dp)` + `setMinHeight(48dp)`。
   1.0 倍字体时高度与设计一致，放大字体时按钮自然长高，**不会**裁切，触控高度始终 ≥ 48dp。
2. 统计页年份按钮显式 `height = "48dp"`、字号由 `label(12sp)` 提到 `body(14sp)`，保持 outlined 样式。
3. 未采用「隐藏裁切部分」之类规避手段。

**实测（1.0 倍字体）**：按钮 144px（48dp），padding 42+42px，文本行高 57px，内容区余量 +3px（不裁切）。
**实测（320dp + 1.3 倍字体）**：按钮自动长到 157px，文本行高 73px，内容区 73px（157-42-42），恰好不裁切。

### 2.5 统计页月份栏精简

v0.2.2 有两个刷新入口（页头 + 月份栏右侧）。v0.2.3 删除月份栏的刷新按钮，
月份栏变为「年份选择按钮 + 月份选择图标 + 当前年月 Badge」，整行 `gravity = center_horizontal`，
控件间距 8dp，左右 padding 16dp；320dp 窄屏自动拆成两行且仍居中，不贴右边缘、不溢出。

实测：页头图标按钮 1 个、月份栏图标按钮 1 个、全页图标按钮共 2 个；年月 Badge 完整可见。

### 2.6 统计卡片

- 双列用 `weight = 1` 等分，两列间距 `hSpacer(cardGap = 12dp)`，两行间距 `spacer(12dp)`。
  （横向行里不能用 `kit.spacer`，其宽度是 `match`，会把卡片挤没。）
- 行容器 `gravity = "start|top"`，避免两张卡片内容行数不同时垂直居中造成错位。
- 卡片内 `padding = cardPadding(16dp)`；图表卡片 `padding = 14dp`。
- 图表宽度由 `chart.measureWidth()` 按「屏宽 − 卡片外边距 − 卡片内 padding」计算，不随外边距变化而过度缩放。
- 窄屏（< 360dp）继续退化为单列（320dp 实测上下排列、卡片最宽 928px ≈ 288dp 可用宽度）。

### 2.7 底部导航双态图标

新增 4 个描边图标定义（同一 24×24 逻辑网格、`width = 1.8`）：`assignment_outline`、
`notifications_outline`、`insights_outline`、`person_outline`。

`TAB_ITEMS` 同时持有 `icon`（填充）与 `iconOutline`（描边）。
`shell.applyTabIcons(nav, colors, selectedId)` 在
`OnItemSelectedListener` 里按当前选中项替换每个 `menuItem` 的图标：
选中用填充版 + `onSecondaryContainer` 着色，未选中用描边版 + `onSurfaceVariant` 着色。
Indicator、标签显隐、选中动画仍由 `BottomNavigationView` 原生逻辑负责，未改动其选中逻辑。

`router.onTabChanged` 回调 `shell.syncTabIcons(key)`，保证「返回键回首页」「登录后复位」
这类**代码侧**切页也会同步图标状态。

**实测**：选中项位图身份 == 填充版缓存位图；未选中项 == 描边版缓存位图；
四项 drawable bounds 均为 72×72px（24dp）；切到通知后通知变填充、作业变描边。

### 2.8 转场动画

新增 `app/ui/motion.lua`，由它统一管理动画，页面内不再写动画代码。

**动画类兼容性检查（真机实测，见 `_probe_transition.txt`）**：

```
OK   com.google.android.material.transition.MaterialFadeThrough
OK   com.google.android.material.transition.MaterialSharedAxis
OK   com.google.android.material.transition.MaterialSharedAxis$Axis
OK   com.google.android.material.transition.platform.MaterialFadeThrough
OK   com.google.android.material.transition.platform.MaterialSharedAxis
OK   androidx.transition.TransitionManager
OK   androidx.transition.TransitionSet / Fade / Slide / ChangeBounds
OK   android.view.animation.PathInterpolator / DecelerateInterpolator
OK   android.provider.Settings$Global
构造探测：MaterialFadeThrough() OK，MaterialSharedAxis(0, true) OK
TransitionManager.beginDelayedTransition(host) OK
animator_duration_scale = 1，transition_animation_scale = 1
```

结论：**Material 官方转场类全部可用**，主路径走官方实现；降级路径仍保留，用于类缺失的运行时。

**实现要点**：
- 顶级页面：`MaterialFadeThrough`，280ms；`router.showTab()` 中调用。
- 二级页：`MaterialSharedAxis(AXIS_X, forward)`，300ms；`router.push()` = forward，`router.back()` = forward=false。
- 视图交换放在转场回调里：先 `TransitionManager.beginDelayedTransition(container, transition)`，
  再在同一帧内 `detachAll()` + `attachView()`，TransitionManager 才能对比出进出视图。
- 并发保护：容器上有转场在跑时先 `TransitionManager.endTransitions(container)`，
  避免两个动画争用同一容器（快速连点导航不会视图叠加，也不会动画结束后页面点不动）。
- 遵循系统动画缩放：`animator_duration_scale ≤ 0.01` 时直接切换，不播放动画。
- 首屏（容器内还没有页面）与 `{ instant = true }` 不播动画；同一 tab 重复选择提前 return。
- 降级路径失败时会把 `alpha / translationX / scaleX / scaleY` 复原，不会把页面留在透明或偏移状态。
- 动画不出现在网络回调、列表刷新路径；页面缓存、滚动位置、`onShow` / `onHide` / `onResume`
  的调用时机与 v0.2.2 一致（转场只包住视图交换，生命周期仍由 router 决定）。

### 2.9 Ripple

`kit.listItem` 在 `onClick` 存在时调用 `M.ripple(container)`，通过
`activity.getTheme().resolveAttribute(android.R.attr.selectableItemBackground)` 套系统 ripple
（自带按下反馈与主题着色，不引入自定义 drawable）。未添加弹跳、大缩放、旋转或长入场动画。

---

## 三、UI 回归测试结果

脚本：`tools/ui_regression.lua`（在 v0.2.2 的 181 项基础上扩展，未另写一套系统）
输出：`_ui_regression.txt`

### 3.1 总体结果

```
设备：360dp 宽，480dpi
=== 汇总：PASS 182 / FAIL 0 ===
结论：全部 UI 结构断言通过
```

### 3.2 v0.2.3 新增断言（全部在真实 NeLuaJ+ Runtime 中执行）

| 分组 | 断言 | 实测证据 |
| --- | --- | --- |
| 我的·图标列 | 图标尺寸 24dp | 72px |
| | 图标容器 24dp | 72×72px |
| | 图标与文字间距 16dp | 48px |
| | 正文左边缘落在 56dp keyline | 168px |
| | 双行行高 ≥ 72dp | 238px |
| | 单行行高 ≥ 56dp | 168px |
| | 整行仍是点击区域 | `isClickable() && hasOnClickListeners()` = true |
| | 不再存在 40dp 图标容器 | 旧尺寸个数 = 0 |
| 我的·边距 | 卡片左右边距真正生效 | 4 张卡片均 left=48px、right=1032px |
| | 账号卡片左边缘 16dp | 48px |
| | 分组卡片之间有呼吸间距 | 133 / 163 / 163 px |
| | 同组用 Divider 分隔 | 4 条分割线 |
| 统计·年份按钮 | 只有一个年份按钮 | 1 |
| | 高度 ≥ 48dp | 144px |
| | 文字未裁切 | 内容区 ≥ 文本行高（余量 +3px） |
| 统计·月份栏 | 只剩 1 个图标按钮 | 1 |
| | 全页图标按钮 2 个 | 2 |
| | 页头保留唯一刷新入口 | 1 |
| 统计·卡片 | 双列间距 12dp | 36px |
| | 双行间距 12dp | 36px |
| | 卡片左右 ≥ 12dp | 7 张卡片全部合规 |
| | 图表完整且不溢出 | 宽图表 2 张（900×570），溢出 0 |
| 底部导航 | 四套双态图标定义齐全 | 无缺失 |
| | 选中项为填充图标 | 位图身份一致 |
| | 未选中项为描边图标（铃铛非填充） | 位图身份一致 |
| | 四图标视觉尺寸一致 | bounds 均 72×72px |
| | 切换后状态正确 | 通知变填充 / 作业变描边 |
| 转场 | 官方转场类可用 | mode = material |
| | 快速连点 4 个主页不抛异常 | 无异常 |
| | 不出现视图叠加 | container childCount 恒为 1 |
| | 转场后页面尺寸正常 | 1080×2118px |
| | 转场后条目仍可点击 | 成功进入 theme_settings |
| | 二级页连续打开 | childCount = 1，currentKey = security |
| | 三次多层返回 | true/true/true，回到 profile |
| | 320dp + 1.3 字体年份按钮不裁切 | 按钮自动长到 157px，行高 73px |

### 3.3 沿用自 v0.2.2 的既有断言（本轮仍全部通过）

作业列表 / 作业详情 / 通知列表 / 通知详情 / 主题设置 / 关于 / 隐私与安全 / 更新日志 /
Auth 迁移的正文挂载与尺寸、320dp 窄屏退化、字体 1.3 倍、文字与背景对比度等，共 120 项。

### 3.4 回归脚本自身的一处测量缺陷（已修正）

过程中出现过一次 3 项失败（统计页卡片数 5、双列间距 -984px、宽图表数 0），排查结论是
**回归脚本的测量时机问题，不是应用缺陷**：

- 该步骤在切换 tab 后立刻读取 `getLeft/getRight`，此时新页面可能尚未完成布局，
  读到的是 0 值，间距算出来自然是负的；
- 用独立诊断脚本 `tools/probe_stats2.lua` 连续验证「首次进入 → 切走 → 切回 → 快速连点后回来」，
  四种状态下统计页均为稳定的 7 张卡片、2 张宽度 900px 的图表，说明页面本身没有问题；
- 修正方式：该步骤先对页面视图做一次显式 `measure`/`layout` 再断言，
  并输出每张卡片的 `宽x高 L T R B` 作为证据。修正后结果稳定为 PASS 182 / FAIL 0。

---

## 四、验证方式说明（哪些是真机执行，哪些是静态检查）

| 验证项 | 执行方式 | 结论 |
| --- | --- | --- |
| `_ui_regression.txt` 全部 182 项 | **真实 NeLuaJ+ Runtime**：真实创建 View、真实 `measure`/`layout` 后读 `getMeasuredWidth/Height`、真实 `performClick()`、真实 `setSelectedItemId()` | PASS 182 / FAIL 0 |
| `_probe_transition.txt` 转场类与构造可用性 | **真实 Runtime** `luajava.bindClass` + 实际构造 + `beginDelayedTransition` 调用 | 全部 OK |
| `_probe_margin.txt` / `_probe_margin2.txt` / `_probe_margin3.txt` 边距根因 | **真实 Runtime** 实测 `LayoutParams` 字段与 `getLeft/getTop` | 定位到 `ViewGroup$LayoutParams` 无边距字段 |
| `_probe_v023.txt` 导航图标身份 | **真实 Runtime** 读取 `menuItem.getIcon()` 的 Bitmap 身份与 bounds | 选中/未选中确实为不同位图 |
| `_probe_stats.txt` 统计页多次切换 | **真实 Runtime** 连续切换 4 次并 dump 卡片几何与图表尺寸 | 每次均 7 张卡片、2 张 900×570 图表 |
| 应用启动无崩溃 | **真实 Runtime** 运行 `main.lua`，捕获 6s 内未捕获异常 | 无崩溃记录 |
| Lua 语法 | 内置 LuaJ++ 解析器语法预检（写入时自动执行） | 全部通过 |
| 转场「看起来是否顺滑」「是否闪白」 | **静态审阅 + 代码路径分析**，未做逐帧录屏 | 需人工目视确认 |
| 深色 / 浅色两套色板下的转场与图标观感 | **静态审阅**（回归脚本在单一模式下运行，按指示未复跑另一模式） | 需人工目视确认 |
| 真实账号下的业务流程 | **未验证**（无有效学生账号），服务层使用桩数据 | 沿用 v0.2.2 既有结论 |

---

## 五、验收标准对照

| 验收项 | 状态 | 依据 |
| --- | --- | --- |
| 我的页面图标列更紧凑整齐 | 达成 | 容器 40→24dp、正文列 72→56dp（实测 168px） |
| 底部导航正确区分填充与描边 | 达成 | 位图身份断言 + bounds 断言 |
| 统计页年份按钮不再裁切 | 达成 | 48dp 最小高度 + wrap；1.0 与 1.3 倍字体均通过 |
| 月份选择栏布局简洁 | 达成 | 重复刷新已删，全页图标按钮 = 2 |
| 卡片不再贴边或紧密堆叠 | 达成 | marginHorizontal 实测生效；cardGap/groupGap 实测 12/10dp |
| 不同页面有自然 MD3 转场 | 达成 | FadeThrough / SharedAxis X 真机类可用，连点与返回均正常 |
| 页面切换不卡顿 | 未量化 | 转场 280/300ms、单容器单转场；未做专业帧率测量 |
| 原有业务功能继续可用 | 达成 | 业务 API / 数据模型 / 登录逻辑未改动；回归脚本原有断言全通过 |

---

## 六、改动文件清单

**新增**
- `app/ui/motion.lua` —— Material Motion 转场统一入口
- `docs/FIX_REPORT_v0.2.3.md` —— 本文档
- `tools/probe_transition.lua` —— 转场类兼容性探测
- `tools/probe_margin.lua` / `tools/probe_margin2.lua` / `tools/probe_margin3.lua` —— 卡片边距根因探测
- `tools/probe_v023.lua` —— 导航图标身份与图标容器尺寸探测
- `tools/probe_stats2.lua` —— 统计页多次切换后的渲染状态探测（用于排除脚本测量时机问题）

**修改**
- `init.lua` —— `ver_name = "0.2.3"`、`ver_code = "203"`
- `app/config.lua` —— `APP_VERSION = "0.2.3"`
- `app/ui/kit.lua` —— `SPACING` 规范、`applyMargins()`、`ripple()`、`marginToPx()`、
  `listItem` Leading Icon 布局、`card` 边距修复、`button` 最小高度、`group` / `sectionTitle` / `pageHeader` 间距
- `app/ui/icons.lua` —— 新增 4 个导航描边图标
- `app/ui/shell.lua` —— `TAB_ITEMS` 双态图标、`applyTabIcons()`、`syncTabIcons()`、`onTabChanged` 接线
- `app/router.lua` —— 接入 `motion`，`showTab` / `push` / `back` / `reset` 支持 `instant` 与转场
- `app/ui/pages/statistics.lua` —— 年份按钮 48dp、月份栏精简居中、卡片间距与 padding 统一
- `app/ui/pages/homework.lua` / `homework_detail.lua` / `notifications.lua` / `profile.lua` /
  `theme_settings.lua` / `about.lua` / `security.lua` / `changelog.lua` / `transfer.lua` —— 统一引用 `kit.SPACING`
- `tools/ui_regression.lua` —— 新增 v0.2.3 断言组（图标列 / 边距 / 统计页 / 导航 / 转场 / 320dp+1.3 字体）
- `README.md` —— 版本号、间距规范、MD3 转场、双态图标、回归数量更新

---

## 七、已知限制（本轮未解决）

1. 转场「是否闪白 / 是否顺滑」属观感判断，只做了代码路径审阅与结构断言，未做逐帧录屏或帧率测量。
2. 深色模式下的回归断言按本轮要求未复跑（脚本支持，切换后重跑即可）。
3. 无真实学生账号，业务数据链路仍以桩数据验证 UI，未验证真实数据渲染。
4. `applyMargins()` 产出的是 `LinearLayout.LayoutParams`，仅适用于 LinearLayout 体系；
   放进其他容器（如 FrameLayout）不会崩但语义不准确，跨容器布局需自行设置对应 `LayoutParams`。
