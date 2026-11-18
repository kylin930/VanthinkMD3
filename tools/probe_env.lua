-- 运行时能力探测脚本（开发期工具，不参与应用运行）
-- 运行方式：以本文件为入口运行，结果写入 _probe_env.txt
local targets = {
  "vinx.material.textfield.MaterialTextField",
  "com.google.android.material.bottomnavigation.BottomNavigationView",
  "com.google.android.material.progressindicator.LinearProgressIndicator",
  "com.google.android.material.progressindicator.CircularProgressIndicator",
  "com.google.android.material.dialog.MaterialAlertDialogBuilder",
  "com.google.android.material.snackbar.Snackbar",
  "com.google.android.material.chip.Chip",
  "com.google.android.material.chip.ChipGroup",
  "com.google.android.material.card.MaterialCardView",
  "com.google.android.material.divider.MaterialDivider",
  "com.google.android.material.button.MaterialButton",
  "com.google.android.material.textview.MaterialTextView",
  "com.google.android.material.appbar.MaterialToolbar",
  "com.google.android.material.appbar.AppBarLayout",
  "com.google.android.material.floatingactionbutton.FloatingActionButton",
  "com.google.android.material.materialswitch.MaterialSwitch",
  "com.google.android.material.tabs.TabLayout",
  "com.google.android.material.bottomsheet.BottomSheetDialog",
  "com.google.android.material.R$style",
  "com.google.android.material.R$attr",
  "com.google.android.material.R$drawable",
  "androidx.appcompat.app.AppCompatDelegate",
  "androidx.security.crypto.EncryptedSharedPreferences",
  "androidx.security.crypto.MasterKey",
  "com.google.zxing.qrcode.QRCodeWriter",
  "com.google.zxing.MultiFormatWriter",
  "com.google.zxing.BarcodeFormat",
  "com.google.zxing.qrcode.QRCodeReader",
  "com.google.zxing.common.HybridBinarizer",
  "androidx.recyclerview.widget.RecyclerView",
  "androidx.core.widget.NestedScrollView",
  "androidx.swiperefreshlayout.widget.SwipeRefreshLayout",
  "android.graphics.Canvas",
  "android.graphics.Bitmap",
  "android.graphics.Paint",
  "android.text.StaticLayout",
  "android.provider.MediaStore",
  "android.util.Base64",
  "com.androlua.adapter.LuaRecyclerAdapter",
  "java.util.UUID",
  "javax.crypto.Cipher",
  "github.daisukiKaffuChino.utils.LuaThemeUtil",
  "androidx.core.view.WindowCompat",
  "com.google.android.material.color.DynamicColors",
}

local out = {}
local function log(s) out[#out + 1] = s end

log("== class availability ==")
for _, name in ipairs(targets) do
  local ok, res = pcall(luajava.bindClass, name)
  log(string.format("%s\t%s", ok and "OK " or "MISS", name))
end

log("")
log("== activity api ==")
local function has(name)
  local ok, v = pcall(function() return activity[name] end)
  log(string.format("%s\t%s (%s)", ok and (v ~= nil and "OK " or "NIL") or "ERR", name, tostring(v)))
end
for _, n in ipairs({ "dynamicColor", "isNightMode", "setSharedData", "getSharedData",
  "dpToPx", "spToPx", "delay", "addOnBackPressedCallback", "getVersionName", "loadBitmap",
  "loadImage", "getUriForPath", "resultLauncher", "permissionLauncher", "requestStoragePermission",
  "getLuaDir", "getLuaExtDir", "getMediaDir", "themeUtil", "harmonizeColor", "isColorLight",
  "setTheme", "getTheme", "startPackage", "checkPermission", "setAllowThread", "getImageLoader" }) do
  has(n)
end

log("")
log("== globals ==")
for _, n in ipairs({ "okhttp", "okHttp", "http", "json", "file", "res", "ext", "saf", "xTask",
  "task", "thread", "timer", "call", "import", "loadlayout", "ColorUtil", "MDC_R", "Http", "R" }) do
  local ok, v = pcall(function() return _G[n] end)
  log(string.format("%s\t%s (%s)", ok and (v ~= nil and "OK " or "NIL") or "ERR", n, type(v)))
end

log("")
log("== themeUtil fields ==")
local ok, err = pcall(function()
  local t = activity.themeUtil
  log("primary.main = " .. tostring(t.primary.main))
  log("surface.main = " .. tostring(t.surface.main))
  log("surface.container = " .. tostring(t.surface.container))
  log("surface.containerLow = " .. tostring(t.surface.containerLow))
  log("surface.onVariant = " .. tostring(t.surface.onVariant))
  log("outline.variant = " .. tostring(t.outline.variant))
  log("error.main = " .. tostring(t.error.main))
  log("tertiary.main = " .. tostring(t.tertiary.main))
end)
if not ok then log("themeUtil error: " .. tostring(err)) end

local ok2, err2 = pcall(function()
  log("isNightMode = " .. tostring(activity.isNightMode()))
  log("versionName = " .. tostring(activity.getVersionName("1.0")))
  log("mediaDir = " .. tostring(activity.getMediaDir()))
  log("luaDir = " .. tostring(activity.getLuaDir()))
end)
if not ok2 then log("misc error: " .. tostring(err2)) end

local text = table.concat(out, "\n")
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_env.txt"
local okw, errw = pcall(function() file.write(path, text) end)
if not okw then
  pcall(function()
    local LuaFileUtil = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
    LuaFileUtil.writeOrCreate(path, text)
  end)
end
print("probe done")
