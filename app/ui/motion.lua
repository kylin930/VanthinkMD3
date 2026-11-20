-- Material Motion 转场动画：全应用统一入口，页面里不再自己写动画。
--
-- 能力与降级（实机探测结果见 _probe_transition.txt）：
--   com.google.android.material.transition.MaterialFadeThrough  可用
--   com.google.android.material.transition.MaterialSharedAxis   可用
--   androidx.transition.TransitionManager                       可用
-- 三者可用时走官方 Material 转场；任一不可用时自动降级为
-- ViewPropertyAnimator 的「淡入 + 小幅位移/缩放」，不会因为缺少某个动画类而崩溃。
--
-- 设计约束（对应验收要求）：
--   1) 顶级页面切换用 FadeThrough（280ms），二级页进出用 SharedAxis X（300ms）；
--   2) 同一容器上同时只允许一个转场：新转场先 endTransitions 结束旧的，
--      再在同一帧内完成视图交换，快速连点导航不会出现视图叠加；
--   3) 遵循系统「动画时长缩放」：animator_duration_scale 为 0 时直接切换，不播放动画；
--   4) 转场只负责视觉，页面生命周期与视图交换时机仍由 router 决定；
--   5) 动画不放入网络回调、列表刷新路径。
--
-- 用法：
--   motion.fadeThrough(container, function() ... 交换视图 ... end)
--   motion.sharedAxis(container, { forward = true }, function() ... end)

local theme = require "app.ui.theme"

local M = {}

local okFade, MaterialFadeThrough = pcall(luajava.bindClass,
  "com.google.android.material.transition.MaterialFadeThrough")
local okAxis, MaterialSharedAxis = pcall(luajava.bindClass,
  "com.google.android.material.transition.MaterialSharedAxis")
local okTransitionManager, TransitionManager = pcall(luajava.bindClass,
  "androidx.transition.TransitionManager")
local okDecelerate, DecelerateInterpolator = pcall(luajava.bindClass,
  "android.view.animation.DecelerateInterpolator")
local okSettings, SettingsGlobal = pcall(luajava.bindClass, "android.provider.Settings$Global")

M.DURATION_FADE = 280
M.DURATION_AXIS = 300

-- 全局开关：首屏、以及 Activity 重建后的第一次切页由 router 关闭，避免多播放一次转场
M.enabled = true

-- 每个容器上正在进行的转场记账
local active = setmetatable({}, { __mode = "k" })

-- MaterialSharedAxis.Axis 枚举中 X 轴的值
local AXIS_X = 0

M.capabilities = {
  materialFadeThrough = okFade and MaterialFadeThrough ~= nil,
  materialSharedAxis = okAxis and MaterialSharedAxis ~= nil,
  transitionManager = okTransitionManager and TransitionManager ~= nil,
  viewPropertyAnimator = true,
}

if M.capabilities.materialFadeThrough and M.capabilities.materialSharedAxis
  and M.capabilities.transitionManager then
  M.mode = "material"
else
  M.mode = "fallback"
end

-- 系统动画缩放：0 表示用户关闭了动画（无障碍 / 省电习惯），此时直接切换
local function animatorScale()
  if not okSettings or SettingsGlobal == nil then return 1 end
  local ok, value = pcall(function()
    return SettingsGlobal.getFloat(activity.getContentResolver(), "animator_duration_scale", 1.0)
  end)
  if ok and type(value) == "number" then return value end
  return 1
end

function M.animationsEnabled()
  if not M.enabled then return false end
  return animatorScale() > 0.01
end

local function buildTransition(kind, forward, duration)
  if kind == "axis" and M.capabilities.materialSharedAxis then
    local ok, transition = pcall(MaterialSharedAxis, AXIS_X, forward and true or false)
    if ok and transition ~= nil then
      pcall(function() transition.setDuration(duration) end)
      return transition
    end
  end
  if kind == "fade" and M.capabilities.materialFadeThrough then
    local ok, transition = pcall(MaterialFadeThrough)
    if ok and transition ~= nil then
      pcall(function() transition.setDuration(duration) end)
      return transition
    end
  end
  return nil
end

-- 结束容器上残留的转场。快速连续切页时如果不清理，新旧两个转场会同时操作
-- 同一批子视图，表现为视图叠加，或动画结束后页面无法点击。
local function endTransitions(container)
  if not M.capabilities.transitionManager then return end
  pcall(function() TransitionManager.endTransitions(container) end)
  active[container] = nil
end

-- 降级路径：交换视图后对新加入的页面做淡入（+ 轻微位移）
local function fallbackSwap(container, kind, swap, opts, duration)
  local before = {}
  pcall(function()
    local count = container.getChildCount()
    for index = 0, count - 1 do before[container.getChildAt(index)] = true end
  end)

  swap()

  local added = nil
  pcall(function()
    for index = container.getChildCount() - 1, 0, -1 do
      local child = container.getChildAt(index)
      if before[child] == nil then
        added = child
        break
      end
    end
  end)
  if added == nil then return false end

  local slide = theme.dp(24)
  pcall(function()
    added.setAlpha(0)
    if kind == "axis" then
      added.setTranslationX(opts.forward and slide or -slide)
    else
      added.setTranslationX(0)
      added.setScaleX(0.98)
      added.setScaleY(0.98)
    end
  end)

  local ok = pcall(function()
    local animator = added.animate()
    animator.alpha(1)
    animator.translationX(0)
    animator.scaleX(1)
    animator.scaleY(1)
    animator.setDuration(math.floor(duration))
    if okDecelerate and DecelerateInterpolator ~= nil then
      animator.setInterpolator(DecelerateInterpolator(1.6))
    end
    animator.start()
  end)
  if not ok then
    -- 连降级动画都失败时必须复原视图状态，否则页面会停在透明或偏移状态
    pcall(function()
      added.setAlpha(1)
      added.setTranslationX(0)
      added.setScaleX(1)
      added.setScaleY(1)
    end)
    return false
  end
  return true
end

-- 执行一次转场：先启动转场，再在同一帧内交换视图（TransitionManager 的用法要求）
local function run(container, kind, swap, opts)
  local o = opts or {}
  if type(swap) ~= "function" then return false end
  if container == nil then
    pcall(swap)
    return false
  end

  local duration = o.duration or (kind == "axis" and M.DURATION_AXIS or M.DURATION_FADE)

  if not M.animationsEnabled() then
    endTransitions(container)
    pcall(swap)
    return false
  end

  -- 已有转场在跑：先结束旧的（同一帧内），避免两个动画争用同一个容器
  if active[container] then endTransitions(container) end

  local transition = buildTransition(kind, o.forward, duration)
  if transition == nil or not M.capabilities.transitionManager then
    return fallbackSwap(container, kind, swap, o, duration)
  end

  local started = pcall(function()
    TransitionManager.beginDelayedTransition(container, transition)
  end)
  if not started then
    return fallbackSwap(container, kind, swap, o, duration)
  end

  active[container] = true
  local okSwap, err = pcall(swap)
  if not okSwap then
    active[container] = nil
    error(err, 0)
  end
  return true
end

-- 顶级页面切换（作业 / 通知 / 统计 / 我的）：淡出 + 淡入 + 轻微进入缩放
function M.fadeThrough(container, swap, opts)
  return run(container, "fade", swap, opts)
end

-- 二级页面进出：SharedAxis X。opts.forward = true 表示进入，false 表示返回
function M.sharedAxis(container, opts, swap)
  local o = opts or {}
  return run(container, "axis", swap, o)
end

-- 供回归测试与交付文档读取的兼容性信息
function M.describe()
  return {
    mode = M.mode,
    materialFadeThrough = M.capabilities.materialFadeThrough,
    materialSharedAxis = M.capabilities.materialSharedAxis,
    transitionManager = M.capabilities.transitionManager,
    animatorScale = animatorScale(),
    enabled = M.enabled,
  }
end

return M
