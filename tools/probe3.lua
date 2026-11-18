-- 探测（三）：最小化验证文件写入 + 异步回调 + 计时器
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe3.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush()
  local ok, e = pcall(function() file.write(path, table.concat(out, "\n")) end)
  if not ok then print("flush fail: " .. tostring(e)) end
end

log("start " .. os.time())
flush()

function onError(err, msg)
  log("ONERROR " .. tostring(err) .. " | " .. tostring(msg))
  flush()
  return true
end

-- 计时器
local ok1, e1 = pcall(function()
  local t = timer(function()
    log("timer fired")
    flush()
  end, 500, 0)
  log("timer created " .. tostring(t))
end)
if not ok1 then log("timer err " .. tostring(e1)) end

-- activity.delay
local ok2, e2 = pcall(function()
  activity.delay(1500, function()
    log("delay fired")
    flush()
  end)
end)
if not ok2 then log("delay err " .. tostring(e2)) end

-- 异步 okHttp
local ok3, e3 = pcall(function()
  okHttp.get("https://zxzjverlog.930390.xyz/api/version", {}, function(code, body)
    log("okHttp.get code=" .. tostring(code) .. " body=" .. tostring(body):sub(1, 200))
    flush()
  end)
end)
if not ok3 then log("okHttp err " .. tostring(e3)) end

-- xTask
local ok4, e4 = pcall(function()
  xTask {
    dispatcher = "io",
    task = function()
      local ok, res = pcall(function() return okhttp.get("https://zxzjverlog.930390.xyz/api/version") end)
      if not ok then return "SYNC_ERR:" .. tostring(res) end
      local body = "?"
      pcall(function() body = res.body().string() end)
      return "SYNC_OK code=" .. tostring(pcall(function() return res.code() end)) .. " body=" .. tostring(body):sub(1, 120)
    end,
    callback = function(r)
      log("xTask callback: " .. tostring(r))
      flush()
    end,
  }
end)
if not ok4 then log("xTask err " .. tostring(e4)) end

flush()
print("probe3 started")
