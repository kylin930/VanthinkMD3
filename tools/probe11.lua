-- 探测（十一）：POST 变体、对话框回调、Insets 监听、Chip、Path 图标
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe11.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err):sub(1, 500)) end
  flush()
end

-- 复位夜间模式
pcall(function()
  local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")
  AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
end)

step("post-sync-table", function()
  local resp = okhttp.post("https://api.wxzxzj.com/api/notice/getNoticeList",
    { type = "notice", page = "1", page_size = "2" },
    { Authorization = "invalid_probe", ["Content-Type"] = "application/x-www-form-urlencoded" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[post-sync-table] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("post-sync-json", function()
  local resp = okhttp.postJson("https://api.wxzxzj.com/api/notice/getNoticeList",
    json.encode({ type = "notice", page = "1", page_size = "2" }),
    { Authorization = "invalid_probe" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[post-sync-json] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("post-async-form", function()
  okHttp.post("https://api.wxzxzj.com/api/notice/getNoticeList",
    "type=notice&page=1&page_size=2",
    { Authorization = "invalid_probe", ["Content-Type"] = "application/x-www-form-urlencoded" },
    function(code, body)
      log("[post-async-form] code=" .. tostring(code) .. " body=" .. tostring(body):sub(1, 300))
      flush()
    end)
end)

step("dialog", function()
  local Builder = luajava.bindClass("com.google.android.material.dialog.MaterialAlertDialogBuilder")
  local dialog = Builder(activity)
    .setTitle("测试")
    .setMessage("内容")
    .setPositiveButton("确定", function() log("[dialog] positive clicked") flush() end)
    .setNegativeButton("取消", nil)
    .create()
  log("[dialog] created=" .. tostring(dialog))
  dialog.show()
  activity.delay(600, function() dialog.dismiss() end)
end)

step("chip", function()
  local Chip = luajava.bindClass("com.google.android.material.chip.Chip")
  local ChipGroup = luajava.bindClass("com.google.android.material.chip.ChipGroup")
  local group = ChipGroup(activity)
  local chip = Chip(activity)
  chip.setText("全部")
  chip.setCheckable(true)
  chip.setChecked(true)
  group.addView(chip)
  chip.setOnCheckedChangeListener(function(v, checked)
    log("[chip] checked=" .. tostring(checked))
    flush()
  end)
  log("[chip] group=" .. tostring(group.getChildCount()))
end)

step("icons-path", function()
  local Bitmap = luajava.bindClass("android.graphics.Bitmap")
  local Config = luajava.bindClass("android.graphics.Bitmap$Config")
  local Canvas = luajava.bindClass("android.graphics.Canvas")
  local Paint = luajava.bindClass("android.graphics.Paint")
  local Path = luajava.bindClass("android.graphics.Path")
  local BitmapDrawable = luajava.bindClass("android.graphics.drawable.BitmapDrawable")
  local density = activity.getResources().getDisplayMetrics().density
  local size = math.floor(24 * density + 0.5)
  local bmp = Bitmap.createBitmap(size, size, Config.ARGB_8888)
  local canvas = Canvas(bmp)
  local paint = Paint()
  paint.setAntiAlias(true)
  paint.setStyle(android.graphics.Paint.Style.STROKE)
  paint.setStrokeWidth(2 * density)
  paint.setStrokeCap(android.graphics.Paint.Cap.ROUND)
  paint.setColor(-16750498)
  local p = Path()
  p.moveTo(4 * density, 6 * density)
  p.lineTo(20 * density, 6 * density)
  p.moveTo(4 * density, 12 * density)
  p.lineTo(20 * density, 12 * density)
  p.moveTo(4 * density, 18 * density)
  p.lineTo(14 * density, 18 * density)
  canvas.drawPath(p, paint)
  local d = BitmapDrawable(activity.getResources(), bmp)
  log("[icons] drawable=" .. tostring(d))
  local iv = luajava.bindClass("android.widget.ImageView")(activity)
  iv.setImageDrawable(d)
  log("[icons] imageview ok")
end)

step("insets-listener", function()
  local ViewCompat = luajava.bindClass("androidx.core.view.ViewCompat")
  local WindowInsetsCompat = luajava.bindClass("androidx.core.view.WindowInsetsCompat")
  local view = luajava.bindClass("android.widget.FrameLayout")(activity)
  local ok, err = pcall(function()
    ViewCompat.setOnApplyWindowInsetsListener(view, function(v, insets)
      local bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
      log("[insets] top=" .. tostring(bars.top) .. " bottom=" .. tostring(bars.bottom))
      flush()
      return insets
    end)
  end)
  log("[insets] listener ok=" .. tostring(ok) .. " " .. tostring(err))
end)

step("textinput-password", function()
  local MaterialTextField = luajava.bindClass("vinx.material.textfield.MaterialTextField")
  local S = luajava.bindClass("com.google.android.material.R$style")
  local TextInputLayout = luajava.bindClass("com.google.android.material.textfield.TextInputLayout")
  local field = MaterialTextField(activity)
  field.setHint("密码")
  field.setEndIconMode(TextInputLayout.END_ICON_PASSWORD_TOGGLE)
  field.setText("secret")
  log("[mtf] text=" .. tostring(field.getText().toString()) .. " endIconMode=" .. tostring(TextInputLayout.END_ICON_PASSWORD_TOGGLE))
end)

step("nav-view", function()
  local BottomNav = luajava.bindClass("com.google.android.material.bottomnavigation.BottomNavigationView")
  local bnv = BottomNav(activity)
  local menu = bnv.getMenu()
  menu.add(0, 1, 0, "作业")
  menu.add(0, 2, 1, "通知")
  menu.add(0, 3, 2, "统计")
  menu.add(0, 4, 3, "我的")
  bnv.setOnItemSelectedListener(function(item)
    log("[bnv] selected=" .. tostring(item.getItemId()))
    flush()
    return true
  end)
  log("[bnv] size=" .. tostring(menu.size()))
end)

log("[end]")
flush()
print("probe11 done")
