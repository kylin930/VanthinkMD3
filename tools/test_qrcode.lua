-- 二维码编码器完整回归测试（开发期，不参与应用运行）
-- 覆盖版本 1~10、每版本最大字节容量、空白/中文/长串；校验：
--   1. 保留模块数符合 ISO 18004（数据模块 = 总码字*8 + 余数位）
--   2. 格式信息与掩码一致（BCH 15,5）
--   3. 逆交织后每个分块满足 RS 生成多项式整除（数学不变量）
--   4. 还原文本与输入完全一致
local LFU = luajava.bindClass("com.nekolaska.io.LuaFileUtil").INSTANCE
local OUT = "/storage/emulated/0/LuaJ/Projects/VanthinkMD3/_test_qrcode.txt"
local lines = {}
local function log(s) lines[#lines + 1] = tostring(s) end
local function flush() pcall(function() LFU.writeOrCreate(OUT, table.concat(lines, "\n")) end) end
flush()

local REMAINDER_BITS = { [1] = 0, [2] = 7, [3] = 7, [4] = 7, [5] = 7, [6] = 7, [7] = 0, [8] = 0, [9] = 0, [10] = 0 }

local function main()
  local qr = require "app.utils.qrcode"
  local VERSION_INFO = qr._internal.versionInfo

  local EXP, LOG = {}, {}
  do
    local v = 1
    for i = 0, 254 do
      EXP[i] = v
      LOG[v] = i
      local d = v * 2
      if d >= 256 then d = d - 256; d = d ~ 0x1D end
      v = d
    end
    EXP[255] = EXP[0]
  end
  local function mul(a, b)
    if a == 0 or b == 0 then return 0 end
    return EXP[(LOG[a] + LOG[b]) % 255]
  end
  local function polyEval(coefs, power)
    local res = 0
    local x = EXP[power % 255]
    for _, c in ipairs(coefs) do res = mul(res, x) ~ c end
    return res
  end

  local function decode(matrix)
    local size = matrix.size
    local modules = matrix.modules
    local version = matrix.version
    local info = VERSION_INFO[version]

    local function getFormat()
      local b = {}
      for i = 0, 5 do b[i] = modules[9][i + 1] and 1 or 0 end
      b[6] = modules[9][8] and 1 or 0
      b[7] = modules[9][9] and 1 or 0
      b[8] = modules[8][9] and 1 or 0
      for i = 9, 14 do b[i] = modules[15 - i][9] and 1 or 0 end
      local value = 0
      for i = 14, 0, -1 do value = value * 2 + b[i] end
      return value
    end
    local formatValue = getFormat()
    local dataBits = math.floor((formatValue ~ 0x5412) / 1024)
    local mask = dataBits % 8
    local eccBits = math.floor(dataBits / 8)
    local expectedFormat = qr._internal.formatBits(mask)
    local expectedValue = 0
    for i = 14, 0, -1 do expectedValue = expectedValue * 2 + expectedFormat[i + 1] end

    local reserved = qr.functionMap(version)
    local reservedCount = 0
    for r = 1, size do
      for c = 1, size do
        if reserved[r][c] then reservedCount = reservedCount + 1 end
      end
    end

    local bits = {}
    local col = size
    local upward = true
    while col >= 1 do
      if col == 7 then col = col - 1 end
      for step = 0, size - 1 do
        local row
        if upward then row = size - step else row = step + 1 end
        for offset = 0, 1 do
          local c = col - offset
          if c >= 1 and not reserved[row][c] then
            local value = modules[row][c]
            if qr._internal.maskCondition(mask, row, c) then value = not value end
            bits[#bits + 1] = value and 1 or 0
          end
        end
      end
      upward = not upward
      col = col - 2
    end

    local codewords = {}
    local i = 1
    while i + 7 <= #bits do
      local byte = 0
      for offset = 0, 7 do byte = byte * 2 + bits[i + offset] end
      codewords[#codewords + 1] = byte
      i = i + 8
    end

    local blocks = info.blocks
    local base = math.floor(info.data / blocks)
    local remainder = info.data % blocks
    local lengths = {}
    for index = 1, blocks do
      lengths[index] = base + ((index > blocks - remainder) and 1 or 0)
    end
    local dataBlocks, eccBlocks = {}, {}
    for index = 1, blocks do dataBlocks[index] = {}; eccBlocks[index] = {} end
    local position = 1
    for idx = 1, base + (remainder > 0 and 1 or 0) do
      for index = 1, blocks do
        if idx <= lengths[index] then
          dataBlocks[index][idx] = codewords[position]
          position = position + 1
        end
      end
    end
    for idx = 1, info.ecPerBlock do
      for index = 1, blocks do
        eccBlocks[index][idx] = codewords[position]
        position = position + 1
      end
    end

    local rsOk = true
    for index = 1, blocks do
      local full = {}
      for _, byte in ipairs(dataBlocks[index]) do full[#full + 1] = byte end
      for _, byte in ipairs(eccBlocks[index]) do full[#full + 1] = byte end
      for power = 0, info.ecPerBlock - 1 do
        if polyEval(full, power) ~= 0 then rsOk = false end
      end
    end

    local dataBytes = {}
    for index = 1, blocks do
      for _, byte in ipairs(dataBlocks[index]) do dataBytes[#dataBytes + 1] = byte end
    end
    local allBits = {}
    for _, byte in ipairs(dataBytes) do
      for offset = 7, 0, -1 do
        allBits[#allBits + 1] = math.floor(byte / (2 ^ offset)) % 2
      end
    end
    local function readBits(start, count)
      local value = 0
      for k = 0, count - 1 do value = value * 2 + allBits[start + k] end
      return value
    end
    local mode = readBits(1, 4)
    local countBits = (version <= 9) and 8 or 16
    local length = readBits(5, countBits)
    local text = {}
    for idx = 1, length do
      text[#text + 1] = string.char(readBits(5 + countBits + (idx - 1) * 8, 8))
    end

    return {
      formatMatches = (formatValue == expectedValue),
      eccLevelBits = eccBits,
      mask = mask,
      rsOk = rsOk,
      mode = mode,
      length = length,
      text = table.concat(text),
      reservedCount = reservedCount,
      bitCount = #bits,
      codewordCount = #codewords,
    }
  end

  local allPass = true
  local function check(label, content, expectVersion, expectFail)
    local result, err = qr.encode(content)
    if expectFail then
      if result == nil then
        log(label .. " 已按预期拒绝: " .. tostring(err) .. " PASS")
      else
        log(label .. " 未拒绝，FAIL")
        allPass = false
      end
      return
    end
    if result == nil then
      log(label .. " encode failed: " .. tostring(err))
      allPass = false
      return
    end
    local decoded = decode(result)
    local info = VERSION_INFO[result.version]
    local expectedReserved = result.size * result.size - (info.total * 8 + REMAINDER_BITS[result.version])
    local checks = {
      text = decoded.text == content,
      rs = decoded.rsOk,
      format = decoded.formatMatches,
      mask = decoded.mask == result.mask,
      mode = decoded.mode == 4,
      ecc = decoded.eccLevelBits == 0,
      reserved = decoded.reservedCount == expectedReserved,
      codewords = decoded.codewordCount == info.total,
      version = (expectVersion == nil) or (result.version == expectVersion),
    }
    local failed = {}
    for name, ok in pairs(checks) do
      if not ok then failed[#failed + 1] = name; allPass = false end
    end
    table.sort(failed)
    log(string.format("%s v%d size=%d mask=%d len=%d/%d %s", label, result.version, result.size,
      result.mask, decoded.length, #content,
      (#failed == 0) and "PASS" or ("FAIL:" .. table.concat(failed, ","))))
    if not checks.reserved then
      log(string.format("   reserved got=%d expected=%d (codewords=%d/%d bits=%d)",
        decoded.reservedCount, expectedReserved, decoded.codewordCount, info.total, decoded.bitCount))
    end
    if not checks.text then
      log("   expected=" .. content:sub(1, 60))
      log("   actual  =" .. decoded.text:sub(1, 60))
    end
  end

  check("空字符串边界-1字符", "A", 1)
  check("v1满容量", string.rep("B", 14), 1)
  check("v2满容量", string.rep("C", 26), 2)
  check("v3满容量", string.rep("D", 42), 3)
  check("v4满容量", string.rep("E", 62), 4)
  check("v5满容量", string.rep("F", 84), 5)
  check("v6满容量", string.rep("G", 106), 6)
  check("v7满容量", string.rep("H", 122), 7)
  check("v8满容量", string.rep("I", 152), 8)
  check("v9满容量", string.rep("J", 180), 9)
  check("v10满容量", string.rep("K", 213), 10)
  check("转移链接", "https://zxzjurl.930390.xyz/a0bcjhy5qu", 3)
  check("完整接口链接", "https://api.wxzxzj.com/api/homework/student/getHomeworkInfo?homework_id=12345", nil)
  check("中文内容（UTF-8 多字节）", "VanthinkMD3 二维码编码器验证：中文内容测试", nil)
  check("超长拒绝", string.rep("Z", 214), nil, true)

  log(allPass and "RESULT: ALL PASS" or "RESULT: FAIL")
end

local ok, err = xpcall(main, function(e) return tostring(e) .. "\n" .. tostring(debug.traceback()) end)
if not ok then
  log("ERROR: " .. tostring(err))
  log("RESULT: FAIL")
end
flush()
print("qrcode test done")
