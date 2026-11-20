-- 极简诊断：确认 showMain 是否执行、mode 是否正确。
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_diag_main.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local ok1, err1 = pcall(function() require("app.ui.theme").bootstrap() end)
log("bootstrap ok=" .. tostring(ok1) .. " err=" .. tostring(err1))
local shell = require "app.ui.shell"
local state = require "app.state"
local ok2, err2 = pcall(function() shell.init() end)
log("init ok=" .. tostring(ok2) .. " err=" .. tostring(err2))
local ok3, err3 = pcall(function() shell.start() end)
log("start ok=" .. tostring(ok3) .. " err=" .. tostring(err3) .. " mode=" .. tostring(shell.mode))

local ok4, err4 = pcall(function() state.setToken("diag_fake_token") end)
log("setToken ok=" .. tostring(ok4) .. " err=" .. tostring(err4) .. " loggedIn=" .. tostring(state.isLoggedIn()))

local ok5, err5 = pcall(function() shell.showMain() end)
log("showMain ok=" .. tostring(ok5) .. " err=" .. tostring(err5) .. " mode=" .. tostring(shell.mode))
log("root childCount=" .. tostring(shell.root.getChildCount()) .. " container=" .. tostring(shell.container))
flush()
