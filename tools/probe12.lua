-- 探测（十二）：二维码/相机/图表相关第三方库可用性 & okHttp 能力
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe12.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end

local candidates = {
  "com.google.zxing.BarcodeFormat",
  "com.google.zxing.qrcode.QRCodeWriter",
  "com.google.zxing.client.android.Intents",
  "com.journeyapps.barcodescanner.BarcodeEncoder",
  "com.journeyapps.barcodescanner.CaptureActivity",
  "cn.bingoogolapple.qrcode.zxing.QRCodeEncoder",
  "androidmads.library.qrgenearator.QRGEncoder",
  "androidmads.library.qrgenearator.QRGContents",
  "com.google.android.gms.vision.barcode.BarcodeDetector",
  "com.google.mlkit.vision.barcode.BarcodeScanner",
  "com.huawei.hms.ml.scan.HmsScan",
  "androidx.camera.core.CameraSelector",
  "androidx.camera.lifecycle.ProcessCameraProvider",
  "android.hardware.camera2.CameraManager",
  "android.util.SparseArray",
  "android.text.TextUtils",
  "android.graphics.Typeface",
  "android.graphics.LinearGradient",
  "android.graphics.Shader",
  "android.graphics.Rect",
  "android.graphics.RectF",
  "android.graphics.Matrix",
  "android.graphics.drawable.GradientDrawable",
  "android.graphics.drawable.RippleDrawable",
  "android.graphics.ColorStateList",
  "android.widget.FrameLayout",
  "android.widget.ScrollView",
  "android.widget.HorizontalScrollView",
  "android.view.ViewGroup",
  "android.view.LayoutInflater",
  "android.content.ClipboardManager",
  "android.content.ClipData",
  "android.net.Uri",
  "android.os.Environment",
  "java.text.SimpleDateFormat",
  "java.util.Date",
  "java.util.Calendar",
  "java.util.TimeZone",
  "java.math.BigDecimal",
  "java.util.Locale",
  "androidx.viewpager2.widget.ViewPager2",
  "com.google.android.material.tabs.TabLayout",
  "com.google.android.material.appbar.CollapsingToolbarLayout",
  "com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton",
  "com.google.android.material.badge.BadgeDrawable",
  "com.google.android.material.search.SearchBar",
  "com.google.android.material.loadingindicator.LoadingIndicator",
  "com.google.android.material.progressindicator.CircularProgressIndicator",
}
for _, n in ipairs(candidates) do
  local ok = pcall(luajava.bindClass, n)
  log((ok and "OK   " or "MISS ") .. n)
end

log("")
log("== okhttp module ==")
do
  local keys = {}
  for k, v in pairs(okhttp) do keys[#keys + 1] = tostring(k) .. "(" .. type(v) .. ")" end
  table.sort(keys)
  log("okhttp fields: " .. table.concat(keys, ", "))
end
do
  local keys = {}
  for k, v in pairs(okHttp) do keys[#keys + 1] = tostring(k) .. "(" .. type(v) .. ")" end
  table.sort(keys)
  log("okHttp fields: " .. table.concat(keys, ", "))
end
log("")

log("== SimpleDateFormat / Date ==")
pcall(function()
  local SDF = luajava.bindClass("java.text.SimpleDateFormat")
  local Date = luajava.bindClass("java.util.Date")
  local f = SDF("yyyy-MM-dd HH:mm:ss")
  log("now=" .. tostring(f.format(Date())))
end)
flush()
print("probe12 done")
