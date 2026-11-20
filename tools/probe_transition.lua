-- 转场动画能力探测（开发期工具，不参与应用运行）
-- 运行方式：以本文件为入口运行，结果写入 _probe_transition.txt

local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_transition.txt"

local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(out, "\n")) end) end
flush()

local targets = {
  "com.google.android.material.transition.MaterialFadeThrough",
  "com.google.android.material.transition.MaterialSharedAxis",
  "com.google.android.material.transition.MaterialSharedAxis$Axis",
  "com.google.android.material.transition.platform.MaterialFadeThrough",
  "com.google.android.material.transition.platform.MaterialSharedAxis",
  "androidx.transition.TransitionManager",
  "androidx.transition.Transition",
  "androidx.transition.TransitionSet",
  "androidx.transition.Fade",
  "androidx.transition.Slide",
  "androidx.transition.ChangeBounds",
  "android.animation.ValueAnimator",
  "android.animation.ObjectAnimator",
  "android.view.animation.PathInterpolator",
  "android.view.animation.DecelerateInterpolator",
  "android.provider.Settings$Global",
}

log("== transition class availability ==")
for _, name in ipairs(targets) do
  local ok = pcall(luajava.bindClass, name)
  log(string.format("%s\t%s", ok and "OK " or "MISS", name))
end

log("")
log("== constructor probe ==")
local okFT, FT = pcall(luajava.bindClass, "com.google.android.material.transition.MaterialFadeThrough")
if okFT and FT ~= nil then
  local ok, instance = pcall(FT)
  log(string.format("%s\tMaterialFadeThrough() -> %s", ok and "OK " or "ERR", tostring(instance)))
  if ok then
    pcall(function() instance.setDuration(280) end)
  end
end

local okSA, SA = pcall(luajava.bindClass, "com.google.android.material.transition.MaterialSharedAxis")
if okSA and SA ~= nil then
  local ok, instance = pcall(SA, 0, true)
  log(string.format("%s\tMaterialSharedAxis(0, true) -> %s", ok and "OK " or "ERR", tostring(instance)))
  if ok then pcall(function() instance.setDuration(300) end) end
end

log("")
log("== TransitionManager probe ==")
local okTM, TM = pcall(luajava.bindClass, "androidx.transition.TransitionManager")
if okTM and TM ~= nil then
  local FrameLayout = luajava.bindClass("android.widget.FrameLayout")
  local host = FrameLayout(activity)
  local okBegin = pcall(function() TM.beginDelayedTransition(host) end)
  log(string.format("%s\tTransitionManager.beginDelayedTransition(host)", okBegin and "OK " or "ERR"))
end

log("")
log("== animator duration scale ==")
pcall(function()
  local resolver = activity.getContentResolver()
  local SettingsGlobal = luajava.bindClass("android.provider.Settings$Global")
  local scale = SettingsGlobal.getFloat(resolver, "animator_duration_scale", 1.0)
  log("animator_duration_scale = " .. tostring(scale))
  local transitionScale = SettingsGlobal.getFloat(resolver, "transition_animation_scale", 1.0)
  log("transition_animation_scale = " .. tostring(transitionScale))
end)

log("")
log("== ViewPropertyAnimator probe ==")
pcall(function()
  local View = luajava.bindClass("android.view.View")
  local view = View(activity)
  local animator = view.animate()
  log(string.format("%s\tview.animate() -> %s", animator ~= nil and "OK " or "MISS", tostring(animator)))
  pcall(function() animator.alpha(0.0) end)
  pcall(function() animator.setDuration(300) end)
end)

flush()
print("probe_transition done -> " .. OUT)
