-- 探测（十）：主题样式与夜间模式、RecyclerView 适配器、SwipeRefresh、POST headers
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe10.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err):sub(1, 400)) end
  flush()
end

step("nelua-styles", function()
  local S = luajava.bindClass("github.znzsofficial.neluaj.R$style")
  local names = { "Theme_NeLuaJ_Material3", "Theme_NeLuaJ_Material3_NoActionBar_ActionOverlay",
    "Theme_NeLuaJ_Material3_DynamicColors_NoActionBar_ActionOverlay",
    "Theme_NeLuaJ_Material3_DynamicColors", "Theme_NeLuaJ_AppCompat",
    "Theme_NeLuaJ_Material3_Light", "Theme_NeLuaJ_Material3_Dark" }
  for _, n in ipairs(names) do
    log("[style] " .. n .. "=" .. tostring(S[n]))
  end
end)

step("post-form", function()
  local resp = okhttp.post("https://api.wxzxzj.com/api/auth/student/login",
    "phone=10000000000&password=probe_invalid_password",
    { ["Content-Type"] = "application/x-www-form-urlencoded" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[post-form] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("login-json-body", function()
  -- 尝试 JSON 体（可能返回不同错误，用于确认参数名是否正确）
  local resp = okhttp.postJson("https://api.wxzxzj.com/api/auth/student/login",
    json.encode({ phone = "10000000000", password = "probe_invalid_password" }), {})
  local body
  pcall(function() body = resp.body().string() end)
  log("[login-json] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("night", function()
  log("[night] isNightMode=" .. tostring(activity.isNightMode()))
  local AppCompatDelegate = luajava.bindClass("androidx.appcompat.app.AppCompatDelegate")
  log("[night] current=" .. tostring(AppCompatDelegate.getDefaultNightMode()))
  local ok, err = pcall(function() AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES) end)
  log("[night] set YES ok=" .. tostring(ok) .. " " .. tostring(err))
  log("[night] after set (before recreate) isNightMode=" .. tostring(activity.isNightMode()))
  local okR, errR = pcall(function() activity.recreate() end)
  log("[night] recreate ok=" .. tostring(okR) .. " " .. tostring(errR))
end)

step("recycler", function()
  local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
  local LinearLayoutManager = luajava.bindClass("androidx.recyclerview.widget.LinearLayoutManager")
  local LuaRecyclerAdapter = luajava.bindClass("com.androlua.adapter.LuaRecyclerAdapter")
  local MaterialTextView = luajava.bindClass("com.google.android.material.textview.MaterialTextView")
  local rv = RecyclerView(activity)
  rv.setLayoutManager(LinearLayoutManager(activity))
  local itemLayout = {
    MaterialTextView,
    id = "title",
    layout_width = "match",
    layout_height = "wrap",
    padding = "16dp",
    textSize = "16sp",
  }
  local adapter = LuaRecyclerAdapter(activity, itemLayout)
  log("[recycler] adapter=" .. tostring(adapter))
  adapter.setDataBinder(function(views, data, holder, position)
    views.title.setText(tostring(data.title))
  end)
  adapter.addAll({ { title = "A" }, { title = "B" }, { title = "C" } })
  rv.setAdapter(adapter)
  log("[recycler] itemCount=" .. tostring(adapter.getItemCount and adapter.getItemCount() or adapter.getItemCount))
end)

step("swipe", function()
  local SwipeRefreshLayout = luajava.bindClass("androidx.swiperefreshlayout.widget.SwipeRefreshLayout")
  local RecyclerView = luajava.bindClass("androidx.recyclerview.widget.RecyclerView")
  local srl = SwipeRefreshLayout(activity)
  local rv = RecyclerView(activity)
  srl.addView(rv)
  log("[swipe] ok " .. tostring(srl) .. " child=" .. tostring(srl.getChildCount()))
  srl.setOnRefreshListener(function() log("[swipe] refresh triggered") flush() end)
end)

step("insets", function()
  local WindowCompat = luajava.bindClass("androidx.core.view.WindowCompat")
  local WindowInsetsControllerCompat = luajava.bindClass("androidx.core.view.WindowInsetsControllerCompat")
  local ViewCompat = luajava.bindClass("androidx.core.view.ViewCompat")
  local window = activity.getWindow()
  log("[insets] window=" .. tostring(window))
  local ok, err = pcall(function() WindowCompat.setDecorFitsSystemWindows(window, false) end)
  log("[insets] setDecorFitsSystemWindows(false) ok=" .. tostring(ok) .. " " .. tostring(err))
  local ok2, err2 = pcall(function() WindowCompat.setDecorFitsSystemWindows(window, true) end)
  log("[insets] restore ok=" .. tostring(ok2) .. " " .. tostring(err2))
end)

step("json", function()
  local t = json.decode('{"a":{"b":[1,2,3]},"c":"中文"}')
  log("[json] a.b[2]=" .. tostring(t.a.b[2]) .. " c=" .. tostring(t.c))
  local e = json.encode({ x = 1, y = "中文" })
  log("[json] encode=" .. tostring(e))
  local arr = json.decode('[{"id":1},{"id":2}]')
  log("[json] arr len=" .. tostring(#arr))
  local empty = json.decode('[]')
  log("[json] empty=" .. tostring(empty) .. " #=" .. tostring(#empty))
end)

log("[end]")
flush()
print("probe10 done")
