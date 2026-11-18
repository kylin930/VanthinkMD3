-- 探测（十四）：xTask 内同步 HTTP 各形态 + 主题属性解析
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe14.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end

local function readBody(res)
  local body
  pcall(function() body = res.body().string() end)
  return tostring(body)
end

xTask {
  dispatcher = "io",
  task = function()
    local lines = {}
    -- 1 GET with headers
    local ok1, r1 = pcall(function()
      return okhttp.get("https://api.wxzxzj.com/api/userinfo/getAccount",
        { Authorization = "invalid_probe" })
    end)
    lines[#lines + 1] = "GET+headers ok=" .. tostring(ok1)
    if ok1 then lines[#lines + 1] = "  code=" .. tostring(r1.code()) .. " body=" .. readBody(r1):sub(1, 160) end

    -- 2 POST 表体（form）
    local ok2, r2 = pcall(function()
      return okhttp.post("https://api.wxzxzj.com/api/auth/student/login",
        { phone = "10000000000", password = "probe_invalid" }, {})
    end)
    lines[#lines + 1] = "POST-table ok=" .. tostring(ok2)
    if ok2 then lines[#lines + 1] = "  code=" .. tostring(r2.code()) .. " body=" .. readBody(r2):sub(1, 200)
    else lines[#lines + 1] = "  err=" .. tostring(r2):sub(1, 200) end

    -- 3 POST JSON
    local ok3, r3 = pcall(function()
      return okhttp.postJson("https://api.wxzxzj.com/api/notice/getNoticeList",
        json.encode({ type = "notice", page = "1", page_size = "2" }),
        { Authorization = "invalid_probe" })
    end)
    lines[#lines + 1] = "POST-json ok=" .. tostring(ok3)
    if ok3 then lines[#lines + 1] = "  code=" .. tostring(r3.code()) .. " body=" .. readBody(r3):sub(1, 200)
    else lines[#lines + 1] = "  err=" .. tostring(r3):sub(1, 200) end

    -- 4 POST 表体 + headers
    local ok4, r4 = pcall(function()
      return okhttp.post("https://api.wxzxzj.com/api/notice/getNoticeList",
        { type = "notice", page = "1", page_size = "2" },
        { Authorization = "invalid_probe" })
    end)
    lines[#lines + 1] = "POST-table+headers ok=" .. tostring(ok4)
    if ok4 then lines[#lines + 1] = "  code=" .. tostring(r4.code()) .. " body=" .. readBody(r4):sub(1, 200)
    else lines[#lines + 1] = "  err=" .. tostring(r4):sub(1, 200) end

    return table.concat(lines, "\n")
  end,
  callback = function(result)
    log("[xTask] " .. tostring(result))
    flush()

    -- 主题属性解析测试
    local TypedValue = luajava.bindClass("android.util.TypedValue")
    local theme = activity.getTheme()
    local function resolve(attrName)
      local MaterialR = luajava.bindClass("com.google.android.material.R$attr")
      local id = MaterialR[attrName]
      if not id then return "noattr" end
      local tv = TypedValue()
      local found = theme.resolveAttribute(id, tv, true)
      return tostring(found) .. "/" .. tostring(tv.data)
    end
    log("[attr] before dynamicColor colorPrimary=" .. resolve("colorPrimary") .. " colorSurface=" .. resolve("colorSurface"))

    local okd, errd = pcall(function() activity.dynamicColor(0xFFB3261E) end)
    log("[attr] dynamicColor ok=" .. tostring(okd) .. " " .. tostring(errd))
    log("[attr] after dynamicColor colorPrimary=" .. resolve("colorPrimary") .. " colorSurface=" .. resolve("colorSurface"))
    log("[attr] themeUtil.primary.main=" .. tostring(activity.themeUtil.primary.main))
    flush()
    print("probe14 done")
  end,
}
