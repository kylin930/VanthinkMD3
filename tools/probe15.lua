-- 探测（十五）：Auth 迁移第三方接口的实际响应结构
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe15.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end) end

local function bodyOf(res)
  local text = ""
  pcall(function() text = res.body().string() end)
  return tostring(text)
end

xTask {
  dispatcher = "io",
  task = function()
    local lines = {}
    -- 1) create
    local ok1, r1 = pcall(function()
      return okhttp.get("https://zxzjurl.930390.xyz/create?auth=probe_token_value")
    end)
    lines[#lines + 1] = "create ok=" .. tostring(ok1)
    local createdUrl = nil
    if ok1 then
      local body = bodyOf(r1)
      lines[#lines + 1] = "  code=" .. tostring(r1.code()) .. " body=" .. body:sub(1, 300)
      local okj, t = pcall(function() return json.decode(body) end)
      if okj and type(t) == "table" then createdUrl = t.url end
    end

    -- 2) status
    if createdUrl ~= nil then
      local code = string.match(createdUrl, "([^/]+)$")
      lines[#lines + 1] = "  code=" .. tostring(code)
      local ok2, r2 = pcall(function()
        return okhttp.get("https://zxzjurl.930390.xyz/status/" .. tostring(code))
      end)
      lines[#lines + 1] = "status ok=" .. tostring(ok2)
      if ok2 then
        lines[#lines + 1] = "  code=" .. tostring(r2.code()) .. " body=" .. bodyOf(r2):sub(1, 400)
      else
        lines[#lines + 1] = "  err=" .. tostring(r2):sub(1, 200)
      end

      -- 3) 领取该 url
      local ok3, r3 = pcall(function() return okhttp.get(createdUrl) end)
      lines[#lines + 1] = "receive ok=" .. tostring(ok3)
      if ok3 then
        lines[#lines + 1] = "  code=" .. tostring(r3.code()) .. " body=" .. bodyOf(r3):sub(1, 400)
      else
        lines[#lines + 1] = "  err=" .. tostring(r3):sub(1, 200)
      end

      -- 4) 再次领取（验证一次性）
      local ok4, r4 = pcall(function() return okhttp.get(createdUrl) end)
      lines[#lines + 1] = "receive2 ok=" .. tostring(ok4)
      if ok4 then
        lines[#lines + 1] = "  code=" .. tostring(r4.code()) .. " body=" .. bodyOf(r4):sub(1, 400)
      end
    end
    return table.concat(lines, "\n")
  end,
  callback = function(result)
    log("[transfer] " .. tostring(result))
    flush()
    print("probe15 done")
  end,
}
