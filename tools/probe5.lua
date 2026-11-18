-- 探测（五）：最小文件写入验证
local p1 = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_probe5.txt"
local ok1, e1 = pcall(function() file.write(p1, "hello5") end)
local p2 = activity.getLuaDir() .. "/_probe5b.txt"
local ok2, e2 = pcall(function() file.write(p2, "hello5b") end)
local p3 = activity.getLuaExtDir() .. "/_probe5c.txt"
local ok3, e3 = pcall(function() file.write(p3, "hello5c") end)
local LuaFileUtil = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local ok4, e4 = pcall(function() LuaFileUtil.writeOrCreate(p1, "hello5-lfu") end)

print("probe5", tostring(ok1), tostring(ok2), tostring(ok3), tostring(ok4))
print("errs", tostring(e1), tostring(e2), tostring(e3), tostring(e4))
print("luaDir", activity.getLuaDir())
print("extDir", activity.getLuaExtDir())
