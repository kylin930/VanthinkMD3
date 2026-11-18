-- 探测（十三）：分步 flush 的类可用性探测
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe13.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err):sub(1, 300)) end
  flush()
end

local candidates = {
  "com.google.zxing.BarcodeFormat",
  "com.google.zxing.qrcode.QRCodeWriter",
  "com.journeyapps.barcodescanner.BarcodeEncoder",
  "cn.bingoogolapple.qrcode.zxing.QRCodeEncoder",
  "androidmads.library.qrgenearator.QRGEncoder",
  "com.google.android.gms.vision.barcode.BarcodeDetector",
  "com.google.mlkit.vision.barcode.BarcodeScanner",
  "androidx.camera.core.CameraSelector",
  "androidx.camera.lifecycle.ProcessCameraProvider",
  "android.hardware.camera2.CameraManager",
  "android.util.SparseArray",
  "android.graphics.Typeface",
  "android.graphics.LinearGradient",
  "android.graphics.Shader",
  "android.graphics.RectF",
  "android.graphics.drawable.GradientDrawable",
  "android.graphics.drawable.RippleDrawable",
  "android.content.res.ColorStateList",
  "android.widget.FrameLayout",
  "android.widget.ScrollView",
  "android.content.ClipboardManager",
  "android.content.ClipData",
  "java.text.SimpleDateFormat",
  "java.util.Calendar",
  "java.util.Locale",
  "androidx.viewpager2.widget.ViewPager2",
  "com.google.android.material.badge.BadgeDrawable",
  "com.google.android.material.progressindicator.CircularProgressIndicator",
}
for _, n in ipairs(candidates) do
  local ok = pcall(luajava.bindClass, n)
  log((ok and "OK   " or "MISS ") .. n)
end
flush()

step("okhttp-fields", function()
  local ok, err = pcall(function()
    local keys = {}
    for k, v in pairs(okhttp) do keys[#keys + 1] = tostring(k) .. "(" .. type(v) .. ")" end
    table.sort(keys)
    log("okhttp fields: " .. table.concat(keys, ", "))
  end)
  if not ok then log("okhttp pairs failed: " .. tostring(err):sub(1, 120)) end
end)

step("okHttp-type", function()
  log("okHttp tostring=" .. tostring(okHttp))
  local m = pcall(function() return okHttp.get end)
  log("okHttp.get pcall=" .. tostring(m))
end)

step("date", function()
  local SDF = luajava.bindClass("java.text.SimpleDateFormat")
  local Date = luajava.bindClass("java.util.Date")
  local f = SDF("yyyy-MM-dd HH:mm:ss")
  log("now=" .. tostring(f.format(Date())))
end)

step("calendar", function()
  local Calendar = luajava.bindClass("java.util.Calendar")
  local c = Calendar.getInstance()
  log("year=" .. tostring(c.get(Calendar.YEAR)) .. " month=" .. tostring(c.get(Calendar.MONTH) + 1))
end)

step("typeface", function()
  local Typeface = luajava.bindClass("android.graphics.Typeface")
  log("DEFAULT_BOLD=" .. tostring(Typeface.DEFAULT_BOLD))
end)

log("[end]")
flush()
print("probe13 done")
