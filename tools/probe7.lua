-- 探测（七）：加密、图片/Canvas、分享 Intent、底部导航、主题
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe7.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err)) end
  flush()
end

local JavaString = luajava.bindClass("java.lang.String")

step("http-sync", function()
  local res = okhttp.get("https://zxzjverlog.930390.xyz/api/version")
  log("[http-sync] type=" .. type(res) .. " text=" .. tostring(res):sub(1, 100))
  if type(res) == "userdata" then
    log("[http-sync] code=" .. tostring(res.code()))
    log("[http-sync] body=" .. tostring(res.body().string()):sub(1, 100))
  end
end)

step("keystore", function()
  local KeyStore = luajava.bindClass("java.security.KeyStore")
  local KeyGenerator = luajava.bindClass("javax.crypto.KeyGenerator")
  local KeyGenParameterSpec = luajava.bindClass("android.security.keystore.KeyGenParameterSpec")
  local Cipher = luajava.bindClass("javax.crypto.Cipher")
  local Base64 = luajava.bindClass("android.util.Base64")
  local ks = KeyStore.getInstance("AndroidKeyStore")
  ks.load(nil)
  if not ks.containsAlias("vanthink_probe") then
    local builder = KeyGenParameterSpec.Builder("vanthink_probe",
      KeyGenParameterSpec.PURPOSE_ENCRYPT + KeyGenParameterSpec.PURPOSE_DECRYPT)
    builder.setBlockModes({ "GCM" })
    builder.setEncryptionPaddings({ "NoPadding" })
    local kg = KeyGenerator.getInstance("AES", "AndroidKeyStore")
    kg.init(builder.build())
    kg.generateKey()
  end
  local key = ks.getKey("vanthink_probe", nil)
  local enc = Cipher.getInstance("AES/GCM/NoPadding")
  enc.init(Cipher.ENCRYPT_MODE, key)
  local ct = enc.doFinal(JavaString("hello-token").getBytes("UTF-8"))
  local iv = enc.getIV()
  local b64 = Base64.encodeToString(ct, Base64.NO_WRAP)
  local ivb64 = Base64.encodeToString(iv, Base64.NO_WRAP)
  log("[keystore] ct=" .. b64:sub(1, 16) .. " iv=" .. ivb64:sub(1, 8))
  local GCMSpec = luajava.bindClass("javax.crypto.spec.GCMParameterSpec")
  local dec = Cipher.getInstance("AES/GCM/NoPadding")
  dec.init(Cipher.DECRYPT_MODE, key, GCMSpec(128, Base64.decode(ivb64, Base64.NO_WRAP)))
  log("[keystore] roundtrip=" .. tostring(JavaString(dec.doFinal(Base64.decode(b64, Base64.NO_WRAP)))))
end)

step("image", function()
  local Bitmap = luajava.bindClass("android.graphics.Bitmap")
  local Config = luajava.bindClass("android.graphics.Bitmap$Config")
  local Canvas = luajava.bindClass("android.graphics.Canvas")
  local Paint = luajava.bindClass("android.graphics.Paint")
  local bmp = Bitmap.createBitmap(120, 60, Config.ARGB_8888)
  local canvas = Canvas(bmp)
  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setColor(0xFF0061A4)
  canvas.drawRect(0, 0, 120, 60, paint)
  local p = activity.getMediaDir().getAbsolutePath() .. "/probe7.png"
  local fos = luajava.bindClass("java.io.FileOutputStream")(p)
  bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
  fos.flush(); fos.close()
  local FileCls = luajava.bindClass("java.io.File")
  log("[image] path=" .. p .. " size=" .. tostring(FileCls(p).length()))
  log("[image] uri=" .. tostring(activity.getUriForPath(p)))
end)

step("share-intent", function()
  local Intent = luajava.bindClass("android.content.Intent")
  local p = activity.getMediaDir().getAbsolutePath() .. "/probe7.png"
  local uri = activity.getUriForPath(p)
  local i = Intent(Intent.ACTION_SEND)
  i.setType("image/png")
  i.putExtra(Intent.EXTRA_STREAM, uri)
  i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
  log("[share] intent uri=" .. tostring(uri) .. " action=" .. tostring(i.getAction()))
end)

step("mediastore", function()
  local MediaStore = luajava.bindClass("android.provider.MediaStore")
  local ContentValues = luajava.bindClass("android.content.ContentValues")
  log("[mediastore] Images.Media.EXTERNAL_CONTENT_URI=" .. tostring(MediaStore.Images.Media.EXTERNAL_CONTENT_URI))
  local cv = ContentValues()
  cv.put("_display_name", "vanthink_probe.png")
  cv.put("mime_type", "image/png")
  log("[mediastore] cv ok=" .. tostring(cv.size()))
end)

step("bottomnav", function()
  local BottomNav = luajava.bindClass("com.google.android.material.bottomnavigation.BottomNavigationView")
  local bnv = BottomNav(activity)
  local menu = bnv.getMenu()
  menu.add(0, 1, 0, "作业")
  menu.add(0, 2, 1, "通知")
  log("[bottomnav] menu=" .. tostring(menu.size()))
  bnv.setLabelVisibilityMode(1)
  log("[bottomnav] ok")
end)

step("theme", function()
  log("[theme] night=" .. tostring(activity.isNightMode()))
  local t = activity.themeUtil
  log("[theme] primary=" .. tostring(t.primary.main))
  log("[theme] surfaceContainerLow=" .. tostring(t.surface.containerLow))
  log("[theme] outlineVariant=" .. tostring(t.outline.variant))
  log("[theme] onSurfaceVariant=" .. tostring(t.surface.onVariant))
  log("[theme] errorContainer=" .. tostring(t.error.container))
end)

step("prefs", function()
  activity.setSharedData("probe7_key", "probe7_value")
  log("[prefs] read=" .. tostring(activity.getSharedData("probe7_key")))
  log("[prefs] missing=" .. tostring(activity.getSharedData("probe7_missing")))
end)

step("xTask-sync", function()
  local job = xTask {
    dispatcher = "io",
    task = function()
      local ok, res = pcall(function() return okhttp.get("https://zxzjverlog.930390.xyz/api/version") end)
      if not ok then return "ERR:" .. tostring(res) end
      local body = "?"
      pcall(function() body = res.body().string() end)
      return "OK:" .. tostring(body):sub(1, 80)
    end,
    callback = function(r)
      log("[xTask] " .. tostring(r))
      flush()
    end,
  }
  log("[xTask] job=" .. tostring(job))
end)

step("dialog", function()
  local Builder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
  log("[dialog] builder=" .. tostring(Builder ~= nil))
  local builder = Builder(activity)
  log("[dialog] instance ok")
end)

local display = activity.getResources().getDisplayMetrics()
log("[screen] w=" .. tostring(display.widthPixels) .. " h=" .. tostring(display.heightPixels) .. " density=" .. tostring(display.density))
flush()
activity.delay(2500, function()
  log("[final] done")
  flush()
end)
print("probe7 started")
