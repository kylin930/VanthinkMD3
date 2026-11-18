-- 探测（六）：用 LuaFileUtil 持久化诊断结果，分析 file.write 行为
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe6.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush()
  pcall(function() LFU.writeOrCreate(path, table.concat(out, "\n")) end)
end

log("file.write type=" .. tostring(type(file.write)))
local ok1, r1 = pcall(function() return file.write("/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_t1.txt", "abc") end)
log("file.write(abs) ok=" .. tostring(ok1) .. " ret=" .. tostring(r1))
local ok2, r2 = pcall(function() return file.write("_t2.txt", "abc") end)
log("file.write(rel) ok=" .. tostring(ok2) .. " ret=" .. tostring(r2))
log("luaDir=" .. activity.getLuaDir())

log("os=" .. tostring(os))
log("pl_data=" .. tostring(package and package.loaded and package.loaded["pl.data"]))
flush()

-- 计时与异步
local Counter = 0
local function tick(tag)
  Counter = Counter + 1
  log(tag .. " #" .. Counter)
  flush()
end

local okT = pcall(function()
  timer(function() tick("timer") end, 800, 0)
end)
log("timer ok=" .. tostring(okT))

local okD = pcall(function()
  activity.delay(1400, function() tick("delay") end)
end)
log("delay ok=" .. tostring(okD))

local okH = pcall(function()
  okHttp.get("https://zxzjverlog.930390.xyz/api/version", {}, function(code, body)
    log("okHttp.get code=" .. tostring(code) .. " body=" .. tostring(body):sub(1, 300))
    tick("http")
  end)
end)
log("okHttp ok=" .. tostring(okH))
flush()
print("probe6 started")
