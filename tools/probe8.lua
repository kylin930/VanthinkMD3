-- 探测（八）：颜色/图标资源/布局/定时器/DynamicColor
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe8.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err):sub(1, 300)) end
  flush()
end

local function signed(v) if v > 0x7FFFFFFF then return v - 0x100000000 end return v end

step("paint", function()
  local Bitmap = luajava.bindClass("android.graphics.Bitmap")
  local Config = luajava.bindClass("android.graphics.Bitmap$Config")
  local Canvas = luajava.bindClass("android.graphics.Canvas")
  local Paint = luajava.bindClass("android.graphics.Paint")
  local RectF = luajava.bindClass("android.graphics.RectF")
  local bmp = Bitmap.createBitmap(120, 60, Config.ARGB_8888)
  local canvas = Canvas(bmp)
  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setColor(signed(0xFF0061A4))
  canvas.drawRect(RectF(0, 0, 120, 60), paint)
  paint.setColor(signed(0xFFFFFFFF))
  paint.setTextSize(20)
  canvas.drawText("测试 中文", 8, 36, paint)
  local p = activity.getMediaDir().getAbsolutePath() .. "/probe8.png"
  local fos = luajava.bindClass("java.io.FileOutputStream")(p)
  bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
  fos.flush(); fos.close()
  local FileCls = luajava.bindClass("java.io.File")
  log("[paint] size=" .. tostring(FileCls(p).length()) .. " path=" .. p)
end)

step("keystore", function()
  local KeyStore = luajava.bindClass("java.security.KeyStore")
  local KeyGenerator = luajava.bindClass("javax.crypto.KeyGenerator")
  local KeyGenParameterSpec = luajava.bindClass("android.security.keystore.KeyGenParameterSpec")
  local Cipher = luajava.bindClass("javax.crypto.Cipher")
  local Base64 = luajava.bindClass("android.util.Base64")
  local JavaString = luajava.bindClass("java.lang.String")
  local ks = KeyStore.getInstance("AndroidKeyStore")
  ks.load(nil)
  if not ks.containsAlias("vanthink_vault_v1") then
    local builder = KeyGenParameterSpec.Builder("vanthink_vault_v1", 3)
    builder.setBlockModes({ "GCM" })
    builder.setEncryptionPaddings({ "NoPadding" })
    local kg = KeyGenerator.getInstance("AES", "AndroidKeyStore")
    kg.init(builder.build())
    kg.generateKey()
  end
  local key = ks.getKey("vanthink_vault_v1", nil)
  local enc = Cipher.getInstance("AES/GCM/NoPadding")
  enc.init(Cipher.ENCRYPT_MODE, key)
  local ct = enc.doFinal(JavaString("hello-token").getBytes("UTF-8"))
  local iv = enc.getIV()
  local b64 = Base64.encodeToString(ct, Base64.NO_WRAP)
  local ivb64 = Base64.encodeToString(iv, Base64.NO_WRAP)
  log("[keystore] ct=" .. tostring(b64):sub(1, 16))
  local GCMSpec = luajava.bindClass("javax.crypto.spec.GCMParameterSpec")
  local dec = Cipher.getInstance("AES/GCM/NoPadding")
  dec.init(Cipher.DECRYPT_MODE, key, GCMSpec(128, Base64.decode(ivb64, Base64.NO_WRAP)))
  log("[keystore] roundtrip=" .. tostring(JavaString(dec.doFinal(Base64.decode(b64, Base64.NO_WRAP)))))
end)

step("icons", function()
  local names = { "home", "assignment", "notifications", "insights", "person", "refresh",
    "save", "share", "arrow_back", "check", "schedule", "star", "settings", "logout",
    "palette", "info", "qr_code", "camera_alt", "error", "warning", "school", "groups",
    "leaderboard", "bar_chart", "update", "history", "lock", "visibility", "visibility_off",
    "search", "filter_list", "more_vert", "chevron_right", "add", "close", "done_all",
    "download", "cloud_off", "inbox", "task_alt", "stars", "dark_mode", "light_mode",
    "color_lens", "open_in_new", "content_copy", "wifi_off", "trending_up", "list_alt",
    "menu_book", "headphones", "mic", "video_library", "toggle_on", "toggle_off" }
  local okList, missList = {}, {}
  for _, n in ipairs(names) do
    local ok, d = pcall(function() return res.drawable(n) end)
    if ok and d ~= nil then okList[#okList + 1] = n else missList[#missList + 1] = n end
  end
  log("[icons] OK(" .. #okList .. "): " .. table.concat(okList, ","))
  log("[icons] MISS(" .. #missList .. "): " .. table.concat(missList, ","))
  local okT, tinted = pcall(function() return res.drawable("home", activity.themeUtil.primary.main) end)
  log("[icons] tinted=" .. tostring(okT) .. " " .. tostring(tinted))
end)

step("timer", function()
  log("[timer] type=" .. tostring(type(timer)))
  local ok1, r1 = pcall(function() return timer(1000, function() log("[timer] fired1") end) end)
  log("[timer] (ms,fn) ok=" .. tostring(ok1) .. " r=" .. tostring(r1))
  local ok2, r2 = pcall(function() return timer(function() log("[timer] fired2") end, 1000) end)
  log("[timer] (fn,ms) ok=" .. tostring(ok2) .. " r=" .. tostring(r2))
end)

step("layout", function()
  local views = {}
  local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
  local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
  local MaterialCardView = luajava.bindClass("com.google.android.material.card.MaterialCardView")
  local MaterialButton = luajava.bindClass("com.google.android.material.button.MaterialButton")
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local view = loadlayout({
    LinearLayout,
    orientation = "vertical",
    layout_width = "match",
    layout_height = "match",
    BackgroundColor = "?attr/colorSurface",
    padding = "16dp",
    {
      MaterialCardView,
      layout_width = "match",
      layout_height = "wrap",
      radius = "16dp",
      strokeWidth = "1dp",
      strokeColor = "?attr/colorOutlineVariant",
      CardBackgroundColor = "?attr/colorSurfaceContainerLow",
      cardElevation = 0,
      {
        MaterialTextView,
        id = "tv",
        layout_width = "match",
        layout_height = "wrap",
        padding = "16dp",
        text = "标题",
        textSize = "20sp",
        textColor = "?attr/colorOnSurface",
      },
    },
    {
      MaterialButton,
      id = "btn",
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "12dp",
      text = "按钮",
    },
    {
      MaterialTextField,
      id = "field",
      layout_width = "match",
      layout_height = "wrap",
      layout_marginTop = "12dp",
      hint = "手机号",
      singleLine = true,
      style = luajava.bindClass("com.google.android.material.R$style").Widget_Material3_TextInputLayout_OutlinedBox,
    },
  }, views)
  log("[layout] view=" .. tostring(view) .. " tv=" .. tostring(views.tv) .. " btn=" .. tostring(views.btn) .. " field=" .. tostring(views.field))
  if views.field then
    views.field.setText("13800000000")
    log("[layout] field text=" .. tostring(views.field.getText().toString()))
  end
end)

step("dynamiccolor", function()
  log("[dc] before=" .. tostring(activity.themeUtil.primary.main))
  local ok, err = pcall(function() activity.dynamicColor(0xFF009688) end)
  log("[dc] call ok=" .. tostring(ok) .. " " .. tostring(err))
  log("[dc] after=" .. tostring(activity.themeUtil.primary.main))
end)

step("strings", function()
  log("[res] app_title=" .. tostring(res.string.app_title))
  log("[res] layout.main type=" .. tostring(type(res.layout.main)))
end)

step("toast", function()
  local Toast = luajava.bindClass("android.widget.Toast")
  log("[toast] class ok")
end)

step("delegate", function()
  local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")
  log("[delegate] MODE_NIGHT_FOLLOW_SYSTEM=" .. tostring(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM))
  log("[delegate] MODE_NIGHT_YES=" .. tostring(AppCompatDelegate.MODE_NIGHT_YES))
  log("[delegate] MODE_NIGHT_NO=" .. tostring(AppCompatDelegate.MODE_NIGHT_NO))
end)

log("[end]")
flush()
print("probe8 done")
