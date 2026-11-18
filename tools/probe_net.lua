-- 运行时能力探测（二）：HTTP / 加密 / 图片与分享。开发期工具，不参与应用运行。
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush()
  local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe_net.txt"
  pcall(function() file.write(path, table.concat(out, "\n")) end)
end

pcall(function() activity.setAllowThread(true) end)

local VERSION_URL = "https://zxzjverlog.930390.xyz/api/version"

-- 1. 同步 okhttp 返回值形态
do
  local ok, res = pcall(function() return okhttp.get(VERSION_URL) end)
  log("[sync] ok=" .. tostring(ok) .. " type=" .. type(res) .. " value=" .. tostring(res):sub(1, 120))
  if ok and res ~= nil and type(res) == "userdata" then
    local okc, code = pcall(function() return res.code() end)
    log("[sync] code() ok=" .. tostring(okc) .. " -> " .. tostring(code))
    local okb, body = pcall(function() return res.body().string() end)
    log("[sync] body() ok=" .. tostring(okb) .. " -> " .. tostring(body):sub(1, 160))
  end
  if ok and res ~= nil and type(res) == "table" then
    for k, v in pairs(res) do log("[sync] field " .. tostring(k) .. "=" .. tostring(v):sub(1, 80)) end
  end
end

-- 2. xTask 内同步请求
pcall(function()
  local job = xTask {
    dispatcher = "io",
    task = function()
      local ok, res = pcall(function() return okhttp.get(VERSION_URL) end)
      if not ok then return "ERR:" .. tostring(res) end
      return "GET_OK:" .. tostring(res):sub(1, 60)
    end,
    callback = function(result) log("[xTask] " .. tostring(result)) end,
  }
  log("[xTask] job=" .. tostring(job))
end)

-- 3. 异步 okHttp + Lua 表 headers
local function stepAsync()
  okHttp.get(VERSION_URL, { ["X-Probe"] = "1" }, function(code, body, response)
    log("[okHttp.get] code=" .. tostring(code) .. " bodyType=" .. type(body) .. " body=" .. tostring(body):sub(1, 120))
    stepPost()
  end)
end

function stepPost()
  local form = "phone=10000000000&password=probe_invalid_password"
  okHttp.post("https://api.wxzxzj.com/api/auth/student/login", form,
    { ["Content-Type"] = "application/x-www-form-urlencoded" },
    function(code, body)
      log("[okHttp.post form] code=" .. tostring(code) .. " body=" .. tostring(body):sub(1, 240))
      stepPostJson()
    end)
end

function stepPostJson()
  okHttp.postJson("https://api.wxzxzj.com/api/vanclass/getVanclassStudentReport",
    json.encode({ student_id = 1, year = 2025, month = 1 }),
    { ["Authorization"] = "probe-token" },
    function(code, body)
      log("[okHttp.postJson] code=" .. tostring(code) .. " body=" .. tostring(body):sub(1, 240))
      stepKeystore()
    end)
end

function stepKeystore()
  local ok, err = pcall(function()
    local KeyStore = luajava.bindClass("java.security.KeyStore")
    local KeyGenerator = luajava.bindClass("javax.crypto.KeyGenerator")
    local KeyGenParameterSpec = luajava.bindClass("android.security.keystore.KeyGenParameterSpec")
    local Cipher = luajava.bindClass("javax.crypto.Cipher")
    local Base64 = luajava.bindClass("android.util.Base64")
    local JavaString = luajava.bindClass("java.lang.String")
    local ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(nil)
    if not ks.containsAlias("vanthink_token_key") then
      local builder = KeyGenParameterSpec.Builder("vanthink_token_key",
        KeyGenParameterSpec.PURPOSE_ENCRYPT + KeyGenParameterSpec.PURPOSE_DECRYPT)
      builder.setBlockModes({ "GCM" })
      builder.setEncryptionPaddings({ "NoPadding" })
      local kg = KeyGenerator.getInstance("AES", "AndroidKeyStore")
      kg.init(builder.build())
      kg.generateKey()
    end
    local key = ks.getKey("vanthink_token_key", nil)
    local enc = Cipher.getInstance("AES/GCM/NoPadding")
    enc.init(Cipher.ENCRYPT_MODE, key)
    local ct = enc.doFinal(JavaString("hello-token").getBytes("UTF-8"))
    local iv = enc.getIV()
    local encB64 = Base64.encodeToString(ct, Base64.NO_WRAP)
    local ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
    local dec = Cipher.getInstance("AES/GCM/NoPadding")
    local GCMParameterSpec = luajava.bindClass("javax.crypto.spec.GCMParameterSpec")
    dec.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
    local plain = dec.doFinal(Base64.decode(encB64, Base64.NO_WRAP))
    log("[keystore] enc=" .. tostring(encB64):sub(1, 20) .. " iv=" .. tostring(ivB64):sub(1, 12) .. " roundtrip=" .. tostring(JavaString(plain)))
  end)
  if not ok then log("[keystore] ERROR " .. tostring(err)) end
  stepImage()
end

function stepImage()
  local ok, err = pcall(function()
    local Bitmap = luajava.bindClass("android.graphics.Bitmap")
    local BitmapConfig = luajava.bindClass("android.graphics.Bitmap$Config")
    local Canvas = luajava.bindClass("android.graphics.Canvas")
    local Paint = luajava.bindClass("android.graphics.Paint")
    local bmp = Bitmap.createBitmap(64, 64, BitmapConfig.ARGB_8888)
    local canvas = Canvas(bmp)
    local paint = Paint()
    paint.setAntiAlias(true)
    paint.setColor(0xFF0061A4)
    canvas.drawCircle(32, 32, 30, paint)
    local path = activity.getMediaDir().getAbsolutePath() .. "/probe_chart.png"
    local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
    local fos = FileOutputStream(path)
    bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
    fos.flush()
    fos.close()
    local File = luajava.bindClass("java.io.File")
    local f = File(path)
    log("[image] saved=" .. path .. " size=" .. tostring(f.length()))
    local uri = activity.getUriForPath(path)
    log("[image] uri=" .. tostring(uri))
    f.delete()
  end)
  if not ok then log("[image] ERROR " .. tostring(err)) end
  stepUi()
end

function stepUi()
  local ok, err = pcall(function()
    local metrics = activity.getResources().getDisplayMetrics()
    log("[ui] density=" .. tostring(metrics.density) .. " widthPx=" .. tostring(metrics.widthPixels))
    local BottomNav = luajava.bindClass("com.google.android.material.bottomnavigation.BottomNavigationView")
    local bnv = BottomNav(activity)
    local menu = bnv.getMenu()
    menu.add(0, 1, 0, "作业")
    menu.add(0, 2, 1, "通知")
    log("[ui] bottomNav menu size=" .. tostring(menu.size()))
    log("[ui] WindowDecor class=" .. tostring(luajava.bindClass("androidx.core.view.WindowCompat")))
  end)
  if not ok then log("[ui] ERROR " .. tostring(err)) end
  flush()
  print("probe2 done")
end

activity.delay(8000, function()
  log("[timer] flush by delay")
  flush()
end)
local okRun, errRun = pcall(stepAsync)
if not okRun then
  log("[fatal] stepAsync: " .. tostring(errRun))
  flush()
end
