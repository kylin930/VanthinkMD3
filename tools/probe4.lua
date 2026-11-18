-- 探测（四）：确认基本能力，逐步落盘
local path = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe4.txt"
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function flush()
  pcall(function() file.write(path, table.concat(out, "\n")) end)
end

log("A: start")
flush()

log("B: os=" .. tostring(os) .. " os.time=" .. tostring(os and os.time))
log("C: os.date=" .. tostring(os and os.date))
flush()

log("D: type(activity.delay)=" .. tostring(type(activity.delay)))
flush()

local ok, e = pcall(function()
  activity.delay(1200, function()
    log("E: delay fired")
    flush()
  end)
end)
log("F: delay ok=" .. tostring(ok) .. " e=" .. tostring(e))
flush()

print("probe4 done")
