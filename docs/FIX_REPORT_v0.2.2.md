# v0.2.2 UI 渲染与布局修复记录

修复日期：2026-08-01
基线版本：v0.2.1
目标版本：v0.2.2

本次为 Bug Fix，不涉及架构重写、接口变更或页面删除。问题全部集中在**公共 UI 组件与布局参数**，
因此修复主要落在 `app/router.lua` 与 `app/ui/kit.lua`，页面代码只做必要的调用修正。

---

## 一、问题总览

| 现象 | 根因 | 影响范围 |
| --- | --- | --- |
| 所有二级页面只有返回栏，正文空白 | `router.subPage()` 创建了内容容器，但从未挂载 `opts.content` | 作业详情、通知详情、主题设置、更新日志、关于、隐私与安全、Auth 迁移 |
| 「我的」页面条目标题、副标题不显示 | `listItem` / `pageHeader` / `sectionTitle` 的 `textHolder` 写了 `layout_width = "0dp" + layout_weight = 1`，但未换成 `LinearLayout.LayoutParams`，weight 被丢弃 → 宽度恒为 0 | 我的页面全部条目、所有页头、所有分组标题 |
| 统计页面布局被严重挤压 | 横向行内误用纵向 `kit.spacer()`（`layout_width = "match"`）吃掉整行剩余宽度；双列卡片依赖无效 weight | 统计页摘要卡片、年月筛选栏、徽标、图表 |

共同的技术根因只有一条：

> 独立 `loadlayout` 出来的根视图，其 `LayoutParams` 类型由控件自身决定
> （`FrameLayout` → `FrameLayout.LayoutParams`，`MaterialCardView` → `FrameLayout.LayoutParams`）。
> 这类 `LayoutParams` **没有 `weight` 字段**，所以
> `layout_width = "0dp"` + `layout_weight = N` 在根视图上完全无效，
> 宽度（或高度）恒为 0，视图不可见。

项目里已有 `M.applyLinearParams()` 专门处理这件事，但若干组件漏用了它。

---

## 二、`app/router.lua`

### 2.1 二级页正文未挂载（主因）

修复前的 `subPage` 只创建容器：

```lua
local contentHolder = loadlayout({ FrameLayout, ... })
kit.applyLinearParams(contentHolder, { width = "match", height = "0dp", weight = 1 })
root.addView(contentHolder)
return { root = root, bar = bar, content = contentHolder,
         setContent = function(view)
           contentHolder.removeAllViews()
           if view ~= nil then contentHolder.addView(view) end
         end }
```

而调用方普遍写 `router.subPage({ title = "...", content = shell.root })`，
正文被静默丢弃，页面只剩返回栏。

修复后 `setContent(view)` 统一承担三件事，并在 `subPage` 末尾立即挂载 `o.content`：

1. `removeAllViews()` 清空内容容器；
2. 若正文已挂在别的父容器上，先 `parent.removeView(view)`，避免
   `The specified child already has a parent` 异常（二级页实例复用、缓存实例重挂时出现）；
3. 显式设置 `FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)`，保证正文铺满内容区。

`setContent(nil)` 可安全清空内容；`setContent(view)` 接口保留，可继续用于热替换正文。

### 2.2 页面视图挂载安全化

新增本地 `attachView(view)`，替代三处直接 `M.container.addView(page.view)`
（`showTab` / `push` / `back`）：

- 视图若仍有父容器，先移除再重新挂载；
- 显式给 `FrameLayout.LayoutParams(MATCH, MATCH)`，避免非 `FrameLayout` 系页面根视图
  拿到 wrap 尺寸而显示不完整。

`router.push` / `router.back` / `router.showTab` 的调用约定与返回值均未改变。

---

## 三、`app/ui/kit.lua`

### 3.1 补上缺失的 `applyLinearParams`

| 组件 | 修复内容 |
| --- | --- |
| `M.listItem` | `textHolder` 显式 `applyLinearParams({ width = "0dp", height = "wrap", weight = 1 })`；图标容器改为显式 `40dp × 40dp + marginEnd = 16`（原先写在 spec 里的 `layout_marginEnd` 对根视图无效）；标题与副标题增加 `maxLines` 兜底 |
| `M.pageHeader` | `textHolder` 显式给 weight；标题 `maxLines = 2`，不再挤压右侧操作按钮 |
| `M.sectionTitle` | `holder` 显式给 weight，标题 `maxLines = 1`；右侧操作文字正常显示 |
| `M.text` | 新增兜底：`width = "0dp"` 且未声明 `weight` 时自动补 `weight = 1`，消除“宽度 0”隐患 |

`M.applyLinearParams()` 是唯一的 LayoutParams 工具，本次没有新增第二套实现。

### 3.2 新增 `M.hSpacer(widthDp)`

```lua
-- 纵向间距：宽度 match，只能放进竖向 LinearLayout
function M.spacer(heightDp) ... layout_width = "match", layout_height = "<n>dp" ... end

-- 横向间距：固定宽度、高度 wrap（自身高度为 0，不影响父容器高度测量）
function M.hSpacer(widthDp)
  return load({
    Space,
    layout_width = tostring(math.floor(widthDp or 8)) .. "dp",
    layout_height = "wrap",
  })
end
```

`spacer()` 行为**完全未改动**，所有纵向页面不受影响。

### 3.3 新增响应式辅助

```lua
M.COMPACT_WIDTH_DP = 360      -- 窄屏阈值（dp）
M.windowWidthDp()             -- 读取 configuration.screenWidthDp，失败回退 DisplayMetrics
M.isCompactWidth()            -- windowWidthDp() < 360
```

用于统计页在窄屏下把双列改单列，不依赖具体机型像素。

---

## 四、统计页（`app/ui/pages/statistics.lua`）

- 摘要卡片改为 `metricCard(spec, half)`：`half = true` 时 `width = "0dp" + weight = 1`，
  `half = false` 时 `width = "match"`；高度统一 `wrap`
  （父行高度是 `wrap_content`，子视图写 `match_parent` 在滚动容器里会被测成 0 高）。
- 新增 `metricPair(left, right)`：宽屏双列（等分 + `hSpacer(12)` 固定间距），
  窄屏退化为单列（两张卡片上下排列，各占满宽度）。
- 卡片内部数值改为 `width = "0dp" + weight = 1`、单位固定宽度，
  数值再长也不会把「次 / 题 / 天」挤出卡片；标题 / 数值 / 单位 / 说明都加了 `maxLines`。
- 年月筛选栏抽出 `yearButton()`：宽屏一行（`yearButton` + `hSpacer(8)` + `monthPicker`），
  窄屏拆两行，保证按钮与「YYYY 年 M 月」徽标完整可见。
- 横向行内的 `kit.spacer()` 全部替换为 `kit.hSpacer()`。
- 图表：`chart.barChart / lineChart` 的位图宽度由 `measureWidth(insetDp)` 计算，
  扣除卡片外边距 + 内边距（默认 28dp × 2），最小 200dp，
  避免图表被横向控件挤压或缩放失真；图表 `ImageView` 始终 `match_parent` 铺满卡片。

### 实测数据（1080px / 360dp 屏）

| 项 | 修复前 | 修复后 |
| --- | --- | --- |
| 第一行两张摘要卡片宽度 | 宽度 0（weight 丢失） | 474px / 474px（差值 0px） |
| 年月筛选栏 | 徽标被 spacer 挤出 | 年份按钮 264px、徽标 210px 完整显示 |
| 柱状图 / 折线图 | 被横向控件挤压 | 两张图表均 ≥ 200dp 宽 |
| 320dp 窄屏 | 双列被压成零宽 | 单列排列，最宽卡片接近可用宽度 |

---

## 五、其他页面修正

| 文件 | 修改 |
| --- | --- |
| `app/ui/pages/theme_settings.lua` | 预设主题色 6 个色块放进 `HorizontalScrollView`（`wrap` 内容 + 16dp 内边距），320dp 窄屏不再裁切；提示卡片正文补 `weight = 1` |
| `app/ui/pages/homework_detail.lua` | 达标 / 语音徽标之间的 `kit.spacer(0)` + 空格文本替换为 `kit.hSpacer(6)` |
| `app/ui/pages/changelog.lua` | 更新条目正文补 `weight = 1`（原先只有 `width = "0dp"`，长文本宽度为 0） |

---

## 六、回归测试工具

新增 `tools/ui_regression.lua`（开发期工具，不参与运行、不随打包产物发布）。

与旧 `diag_*.lua` 的关键区别：

- 不再用 `pcall(create)` 判“页面正常”——创建成功只说明没抛异常；
- **真实创建 View 并真实测量**（`measure` / `layout`）后读取
  `getMeasuredWidth()` / `getMeasuredHeight()` / `getTop()`；
- 服务层全部替换为固定桩数据，不访问网络，结果可复现；
- 需要布局完成的断言分步骤执行（每步间隔 450ms），避免读到首帧前的 0 值。

覆盖内容：

1. **二级页**：`contentHolder.getChildCount()`、正文是否挂载、正文测量宽高、
   正文是否铺满内容区、返回栏是否存在、正文滚动、返回、再次进入、
   连续进入不同二级页、多层返回。
2. **列表项**：标题 / 副标题实测宽度、图标容器 40dp、右侧箭头、点击区域（向上找可点击祖先）、
   条目高度 ≥ 44dp。
3. **我的页面**：8 个条目逐项检查标题、副标题、点击区域，并真实 `performClick()` 验证跳转与返回。
4. **统计页**：四张摘要卡片标题、两列宽度与是否同一行、年月筛选、图表宽度、
   内容高度 > 视口可滚动、320dp 窄屏单列退化。
5. **设备适配**：`listItem` / `pageHeader` / `sectionTitle` 在 320dp 与 1.3 倍字体缩放下的实测。
6. **主题**：文字与背景对比度检查（向上查找最近的不透明背景），浅色 / 深色模式通用。

运行方式：在 NeLuaJ+ 中直接运行 `tools/ui_regression.lua`，结果写入
`_ui_regression.txt`（逐项 PASS / FAIL）与终端摘要。

本轮结果：**PASS 120 / FAIL 0**，详见 `docs/TEST_REPORT.md`。

---

## 七、未改动的内容

- 路由整体结构（`showTab` / `push` / `back` / 栈模型）与调用约定；
- 网络层（`app/services/*`）、接口地址、数据结构；
- 所有业务页面，无删除、无假页面替代；
- MD3 主题体系（`app/ui/theme.lua`、颜色角色、动态取色）；
- Lua 模块化结构；
- `html/` 原 Web 版源码、已弃用的 Python 服务端；
- 运行时不会执行任何调试代码：`tools/` 不参与入口调用，`main.lua` 未引入诊断脚本。

---

## 八、遗留与未验证项

1. **深色模式的对比度断言未在本轮复跑**。回归脚本会检查当前模式；
   本轮在系统浅色模式下运行通过，深色模式需在真机切换后复跑一次
   （`我的 → 主题设置 → 深色`）。
2. **未用真实学生账号验证数据链路**。回归脚本使用固定桩数据，验证的是
   “给定数据下 UI 是否正确渲染”；真实接口的字段差异仍可能带来长文本 / 极端数值排版问题
   （已用 `maxLines` 与 weight 兜底）。
3. **平板 / 横屏无专属布局**：仍为单列拉伸，`isCompactWidth()` 只在 < 360dp 时改单列。
4. **Auth 迁移真实二维码未复测**：桩数据刻意返回失败以验证失败态正文可见；
   真实生成需要登录态与第三方服务可用。
