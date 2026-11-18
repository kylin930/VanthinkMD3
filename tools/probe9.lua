-- 探测（九）：主题列表、深浅色、Lua drawable、真实登录接口错误体
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe9.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then log("[" .. name .. "] ERROR " .. tostring(err):sub(1, 400)) end
  flush()
end

step("styles", function()
  local Rstyle = luajava.bindClass("com.androlua.R$style") 
  log("[styles] Rtype=" .. tostring(Rstyle))
end)

step("neoluastyles", function()
  local cls = luajava.bindClass("github.znzsofficial.neluaj.R$style")
  log("[styles] cls=" .. tostring(cls))
end)

step("mdcstyles", function()
  local MDCR = luajava.bindClass("com.google.android.material.R$style")
  log("[mdc] Theme_Material3_DayNight_NoActionBar=" .. tostring(MDCR.Theme_Material3_DayNight_NoActionBar))
  log("[mdc] Theme_Material3_Light_NoActionBar=" .. tostring(MDCR.Theme_Material3_Light_NoActionBar))
  log("[mdc] Theme_Material3_Dark_NoActionBar=" .. tostring(MDCR.Theme_Material3_Dark_NoActionBar))
  log("[mdc] Widget_Material3_TextInputLayout_OutlinedBox=" .. tostring(MDCR.Widget_Material3_TextInputLayout_OutlinedBox))
end)

step("lua-drawable", function()
  local d = res.drawable("van_test")
  log("[lua-drawable] = " .. tostring(d))
end)

step("lua-drawable-tinted", function()
  local d = res.drawable("van_test", activity.themeUtil.primary.main)
  log("[lua-drawable2] = " .. tostring(d))
end)

step("login-error", function()
  local form = "phone=10000000000&password=probe_invalid_password"
  local resp = okhttp.post("https://api.wxzxzj.com/api/auth/student/login", form)
  log("[login] resp=" .. tostring(resp):sub(1, 80))
  local body
  pcall(function() body = resp.body().string() end)
  log("[login] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 400))
end)

step("account-noauth", function()
  local resp = okhttp.get("https://api.wxzxzj.com/api/userinfo/getAccount")
  local body
  pcall(function() body = resp.body().string() end)
  log("[account] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("hwlist-noauth", function()
  local resp = okhttp.get("https://api.wxzxzj.com/api/homework/student/getHomeworkList?page=1&page_size=2&time=all&degree=all")
  local body
  pcall(function() body = resp.body().string() end)
  log("[hwlist] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 400))
end)

step("hwlist-badauth", function()
  local resp = okhttp.get("https://api.wxzxzj.com/api/homework/student/getHomeworkList?page=1&page_size=2&time=all&degree=all",
    { Authorization = "invalid_token_probe" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[hwlist2] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 400))
end)

step("notice-badauth", function()
  local resp = okhttp.post("https://api.wxzxzj.com/api/notice/getNoticeList", "type=notice&page=1&page_size=2",
    { Authorization = "invalid_token_probe", ["Content-Type"] = "application/x-www-form-urlencoded" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[notice] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 400))
end)

step("update-api", function()
  local resp = okhttp.get("https://zxzjverlog.930390.xyz/api/version")
  local body
  pcall(function() body = resp.body().string() end)
  log("[update] body=" .. tostring(body):sub(1, 600))
  local ok, t = pcall(function() return json.decode(body) end)
  log("[update] decode ok=" .. tostring(ok) .. " version=" .. tostring(ok and t.version))
end)

step("transfer-create-badauth", function()
  local resp = okhttp.get("https://zxzjurl.930390.xyz/create?auth=invalid_probe")
  local body
  pcall(function() body = resp.body().string() end)
  log("[trans-create] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

step("share-badauth", function()
  local resp = okhttp.get("https://api.wxzxzj.com/api/common/share/commonShare?share_id=1&share_type=homework_student",
    { Authorization = "invalid_token_probe" })
  local body
  pcall(function() body = resp.body().string() end)
  log("[share] code=" .. tostring(resp.code()) .. " body=" .. tostring(body):sub(1, 300))
end)

log("[end]")
flush()
print("probe9 done")
