-- 纯 Lua 二维码编码器（字节模式，纠错等级 M，版本 1~10）
-- 运行时不提供 zxing / MLKit / 任何二维码库（已实测确认），
-- 因此按 ISO/IEC 18004 规范自行实现：GF(256) 有限域、Reed-Solomon 纠错、
-- 交织、掩码评估、格式信息 BCH(15,5) 与版本信息 BCH(18,6)。
-- 输出为布尔矩阵，由 UI 层用原生 Canvas 绘制（不引入 WebView 与外部依赖）。

local M = {}

-- ===== GF(256) =====
local EXP = {}
local LOG = {}
do
  local value = 1
  for i = 0, 254 do
    EXP[i] = value
    LOG[value] = i
    local doubled = value * 2
    if doubled >= 256 then
      -- 模多项式 0x11D：去掉进位后异或低 8 位（0x11D - 0x100 = 0x1D）
      doubled = doubled - 256
      doubled = doubled ~ 0x1D
    end
    value = doubled
  end
  EXP[255] = EXP[0]
end

local function gfMul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[(LOG[a] + LOG[b]) % 255]
end

-- 生成多项式（与 Nayuki 实现一致：长度为 degree 的系数数组）
local function rsDivisor(degree)
  local result = {}
  for i = 1, degree - 1 do result[i] = 0 end
  result[degree] = 1
  local root = 1
  for _ = 1, degree do
    for j = 1, degree do
      result[j] = gfMul(result[j], root)
      if j + 1 <= degree then
        result[j] = result[j] ~ result[j + 1]
      end
    end
    root = gfMul(root, 0x02)
  end
  return result
end

local function rsRemainder(data, divisor)
  local degree = #divisor
  local result = {}
  for i = 1, degree do result[i] = 0 end
  for _, byte in ipairs(data) do
    local factor = byte ~ result[1]
    for i = 1, degree - 1 do
      result[i] = result[i + 1]
    end
    result[degree] = 0
    for i = 1, degree do
      result[i] = result[i] ~ gfMul(divisor[i], factor)
    end
  end
  return result
end

-- ===== 版本/纠错表（等级 M）=====
-- total = 该版本总码字数；ecPerBlock = 每块纠错码字数；blocks = 块数
local VERSION_INFO = {
  [1] = { total = 26, data = 16, ecPerBlock = 10, blocks = 1 },
  [2] = { total = 44, data = 28, ecPerBlock = 16, blocks = 1 },
  [3] = { total = 70, data = 44, ecPerBlock = 26, blocks = 1 },
  [4] = { total = 100, data = 64, ecPerBlock = 18, blocks = 2 },
  [5] = { total = 134, data = 86, ecPerBlock = 24, blocks = 2 },
  [6] = { total = 172, data = 108, ecPerBlock = 16, blocks = 4 },
  [7] = { total = 196, data = 124, ecPerBlock = 18, blocks = 4 },
  [8] = { total = 242, data = 154, ecPerBlock = 22, blocks = 4 },
  [9] = { total = 292, data = 182, ecPerBlock = 22, blocks = 5 },
  [10] = { total = 346, data = 216, ecPerBlock = 26, blocks = 5 },
}

local ALIGNMENT = {
  [1] = {},
  [2] = { 6, 18 },
  [3] = { 6, 22 },
  [4] = { 6, 26 },
  [5] = { 6, 30 },
  [6] = { 6, 34 },
  [7] = { 6, 22, 38 },
  [8] = { 6, 24, 42 },
  [9] = { 6, 26, 46 },
  [10] = { 6, 28, 50 },
}

local ECC_LEVEL_BITS = 0 -- M

local function charCountBits(version)
  if version <= 9 then return 8 end
  return 16
end

local function dataCapacityBytes(version)
  local info = VERSION_INFO[version]
  local usableBits = info.data * 8 - 4 - charCountBits(version)
  return math.floor(usableBits / 8)
end

local function pickVersion(byteLength)
  for version = 1, 10 do
    if dataCapacityBytes(version) >= byteLength then
      return version
    end
  end
  return nil
end

-- ===== 位缓冲（用 0/1 字符串） =====
local function appendBits(buffer, value, length)
  for i = length - 1, 0, -1 do
    local bit = math.floor(value / (2 ^ i)) % 2
    buffer[#buffer + 1] = tostring(bit)
  end
end

local function bitsToBytes(bits)
  local bytes = {}
  local index = 1
  while index <= #bits do
    local byte = 0
    for offset = 0, 7 do
      byte = byte * 2
      if bits[index + offset] == "1" then byte = byte + 1 end
    end
    bytes[#bytes + 1] = byte
    index = index + 8
  end
  return bytes
end

-- ===== 数据码字生成 =====
local function buildCodewords(text, version)
  local info = VERSION_INFO[version]
  local bits = {}
  appendBits(bits, 4, 4) -- 字节模式 0100
  appendBits(bits, #text, charCountBits(version))
  for i = 1, #text do
    appendBits(bits, string.byte(text, i), 8)
  end

  local capacityBits = info.data * 8
  local terminator = math.min(4, capacityBits - #bits)
  for _ = 1, terminator do bits[#bits + 1] = "0" end
  while #bits % 8 ~= 0 do bits[#bits + 1] = "0" end

  local dataBytes = bitsToBytes(bits)
  local pad = 0xEC
  while #dataBytes < info.data do
    dataBytes[#dataBytes + 1] = pad
    if pad == 0xEC then pad = 0x11 else pad = 0xEC end
  end

  -- 分块
  local blocks = info.blocks
  local base = math.floor(info.data / blocks)
  local remainder = info.data % blocks
  local dataBlocks = {}
  local offset = 1
  for index = 1, blocks do
    local length = base
    if index > blocks - remainder then length = base + 1 end
    local chunk = {}
    for i = 1, length do
      chunk[i] = dataBytes[offset]
      offset = offset + 1
    end
    dataBlocks[index] = chunk
  end

  local divisor = rsDivisor(info.ecPerBlock)
  local eccBlocks = {}
  for index = 1, blocks do
    eccBlocks[index] = rsRemainder(dataBlocks[index], divisor)
  end

  -- 交织
  local codewords = {}
  local maxData = base + (remainder > 0 and 1 or 0)
  for i = 1, maxData do
    for index = 1, blocks do
      local chunk = dataBlocks[index]
      if chunk[i] ~= nil then codewords[#codewords + 1] = chunk[i] end
    end
  end
  for i = 1, info.ecPerBlock do
    for index = 1, blocks do
      codewords[#codewords + 1] = eccBlocks[index][i]
    end
  end
  return codewords, info.data
end

-- ===== 矩阵 =====
local function newMatrix(size)
  local modules = {}
  local reserved = {}
  for row = 1, size do
    modules[row] = {}
    reserved[row] = {}
    for col = 1, size do
      modules[row][col] = false
      reserved[row][col] = false
    end
  end
  return modules, reserved
end

local function setFunction(modules, reserved, row, col, dark)
  modules[row][col] = dark
  reserved[row][col] = true
end

local function drawFinder(modules, reserved, row, col, size)
  for dr = -1, 7 do
    for dc = -1, 7 do
      local r = row + dr
      local c = col + dc
      if r >= 1 and r <= size and c >= 1 and c <= size then
        local dark = false
        if dr >= 0 and dr <= 6 and dc >= 0 and dc <= 6 then
          local inRing = (dr == 0 or dr == 6 or dc == 0 or dc == 6)
          local inCore = (dr >= 2 and dr <= 4 and dc >= 2 and dc <= 4)
          dark = inRing or inCore
        end
        setFunction(modules, reserved, r, c, dark)
      end
    end
  end
end

local function drawAlignment(modules, reserved, row, col, size)
  for dr = -2, 2 do
    for dc = -2, 2 do
      local r = row + dr
      local c = col + dc
      if r >= 1 and r <= size and c >= 1 and c <= size then
        local distance = math.max(math.abs(dr), math.abs(dc))
        setFunction(modules, reserved, r, c, distance ~= 1)
      end
    end
  end
end

local function drawFunctionPatterns(modules, reserved, version, size)
  -- 定位图形
  drawFinder(modules, reserved, 1, 1, size)
  drawFinder(modules, reserved, 1, size - 6, size)
  drawFinder(modules, reserved, size - 6, 1, size)

  -- 定时图形（第 7 行与第 7 列，1 基索引；两端由定位图形覆盖）
  for i = 9, size - 8 do
    local dark = (i % 2 == 1)
    setFunction(modules, reserved, 7, i, dark)
    setFunction(modules, reserved, i, 7, dark)
  end

  -- 校正图形（ALIGNMENT 表为标准 0 基坐标，矩阵为 1 基，故 +1）
  local positions = ALIGNMENT[version]
  local count = #positions
  for i = 1, count do
    for j = 1, count do
      local row = positions[i] + 1
      local col = positions[j] + 1
      -- 跳过与定位图形重叠的位置
      local isCorner = (i == 1 and j == 1)
        or (i == 1 and j == count)
        or (i == count and j == 1)
      if not isCorner then
        drawAlignment(modules, reserved, row, col, size)
      end
    end
  end

  -- 预留格式信息区域
  for i = 1, 9 do
    if not reserved[9][i] then setFunction(modules, reserved, 9, i, false) end
    if not reserved[i][9] then setFunction(modules, reserved, i, 9, false) end
  end
  for i = 1, 8 do
    if not reserved[9][size - i + 1] then setFunction(modules, reserved, 9, size - i + 1, false) end
    if not reserved[size - i + 1][9] then setFunction(modules, reserved, size - i + 1, 9, false) end
  end
  setFunction(modules, reserved, size - 7, 9, true) -- 固定深色模块

  -- 版本信息（版本 7 及以上）
  if version >= 7 then
    for i = 1, 6 do
      for j = 1, 3 do
        setFunction(modules, reserved, size - 11 + j, i, false)
        setFunction(modules, reserved, i, size - 11 + j, false)
      end
    end
  end
end

local function placeCodewords(modules, reserved, codewords, size)
  local bitIndex = 1
  local totalBits = #codewords * 8
  local function bitAt(index)
    if index > totalBits then return 0 end
    local byte = codewords[math.floor((index - 1) / 8) + 1]
    local position = (index - 1) % 8
    local divisor = 2 ^ (7 - position)
    return math.floor(byte / divisor) % 2
  end

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
          modules[row][c] = (bitAt(bitIndex) == 1)
          bitIndex = bitIndex + 1
        end
      end
    end
    upward = not upward
    col = col - 2
  end
end

local function maskCondition(mask, row, col)
  local r = row - 1
  local c = col - 1
  if mask == 0 then return (r + c) % 2 == 0 end
  if mask == 1 then return r % 2 == 0 end
  if mask == 2 then return c % 3 == 0 end
  if mask == 3 then return (r + c) % 3 == 0 end
  if mask == 4 then return (math.floor(r / 2) + math.floor(c / 3)) % 2 == 0 end
  if mask == 5 then return (r * c) % 2 + (r * c) % 3 == 0 end
  if mask == 6 then return ((r * c) % 2 + (r * c) % 3) % 2 == 0 end
  return ((r + c) % 2 + (r * c) % 3) % 2 == 0
end

local function applyMask(modules, reserved, mask, size)
  for row = 1, size do
    for col = 1, size do
      if not reserved[row][col] and maskCondition(mask, row, col) then
        modules[row][col] = not modules[row][col]
      end
    end
  end
end

-- 格式信息：BCH(15,5)，生成多项式 0x537，异或掩码 0x5412
local function formatBits(mask)
  local data = ECC_LEVEL_BITS * 8 + mask
  local remainder = data
  for _ = 1, 10 do
    remainder = remainder * 2
    if remainder >= 0x400 then remainder = remainder ~ 0x537 end
  end
  local bits = (data * 1024 + remainder) ~ 0x5412
  local out = {}
  for i = 0, 14 do
    out[#out + 1] = math.floor(bits / (2 ^ i)) % 2
  end
  return out -- out[1] = 最低位
end

local function bit(value, index)
  return math.floor(value / (2 ^ index)) % 2 == 1
end

local function drawFormat(modules, mask, size)
  local bits = formatBits(mask)
  -- bits[i] 对应第 i-1 位（0 = 最低位）
  local function get(index) return bits[index + 1] == 1 end

  for i = 0, 5 do
    modules[9][i + 1] = get(i)
  end
  modules[9][8] = get(6)
  modules[9][9] = get(7)
  modules[8][9] = get(8)
  for i = 9, 14 do
    modules[15 - i][9] = get(i)
  end

  for i = 0, 7 do
    modules[size - i][9] = get(i)
  end
  for i = 8, 14 do
    modules[9][size - 15 + i + 1] = get(i)
  end
  modules[size - 7][9] = true
end

-- 版本信息：BCH(18,6)，生成多项式 0x1F25
local function drawVersion(modules, version, size)
  if version < 7 then return end
  local remainder = version
  for _ = 1, 12 do
    remainder = remainder * 2
    if remainder >= 0x1000 then remainder = remainder ~ 0x1F25 end
  end
  local bits = version * 4096 + remainder
  for i = 0, 17 do
    local dark = bit(bits, i)
    local row = math.floor(i / 3) + 1
    local col = i % 3 + size - 10
    modules[row][col] = dark
    modules[col][row] = dark
  end
end

-- ===== 掩码惩罚评分 =====
local function penaltyScore(modules, size)
  local score = 0

  -- 规则 1：同色连续 >= 5
  local function runScore(getter)
    local result = 0
    for line = 1, size do
      local prev = nil
      local run = 0
      for index = 1, size do
        local value = getter(line, index)
        if value == prev then
          run = run + 1
        else
          if run >= 5 then result = result + 3 + (run - 5) end
          prev = value
          run = 1
        end
      end
      if run >= 5 then result = result + 3 + (run - 5) end
    end
    return result
  end
  score = score + runScore(function(row, col) return modules[row][col] end)
  score = score + runScore(function(row, col) return modules[col][row] end)

  -- 规则 2：2x2 同色块
  for row = 1, size - 1 do
    for col = 1, size - 1 do
      local a = modules[row][col]
      if a == modules[row][col + 1] and a == modules[row + 1][col]
        and a == modules[row + 1][col + 1] then
        score = score + 3
      end
    end
  end

  -- 规则 3：1:1:3:1:1 且一侧有 4 个浅色模块
  local pattern = { true, false, true, true, true, false, true }
  local function matchAt(get, start)
    for index = 0, 6 do
      if get(start + index) ~= pattern[index + 1] then return false end
    end
    return true
  end
  local function lightRun(get, from, count)
    for index = 0, count - 1 do
      if get(from + index) then return false end
    end
    return true
  end
  for line = 1, size do
    for start = 1, size - 6 do
      local getRow = function(index) return modules[line][index] end
      if matchAt(getRow, start) then
        if start - 4 >= 1 and lightRun(getRow, start - 4, 4) then score = score + 40 end
        if start + 11 <= size and lightRun(getRow, start + 7, 4) then score = score + 40 end
      end
      local getCol = function(index) return modules[index][line] end
      if matchAt(getCol, start) then
        if start - 4 >= 1 and lightRun(getCol, start - 4, 4) then score = score + 40 end
        if start + 11 <= size and lightRun(getCol, start + 7, 4) then score = score + 40 end
      end
    end
  end

  -- 规则 4：深色比例偏离 50%
  local dark = 0
  for row = 1, size do
    for col = 1, size do
      if modules[row][col] then dark = dark + 1 end
    end
  end
  local total = size * size
  local k = math.floor((math.abs(dark * 20 - total * 10) + total - 1) / total) - 1
  score = score + k * 10

  return score
end

-- 生成二维码矩阵
-- 返回 { size = n, modules = 二维布尔表, version = v, mask = m }
function M.encode(text)
  local content = tostring(text or "")
  if content == "" then return nil, "内容为空" end
  local version = pickVersion(#content)
  if version == nil then
    return nil, "内容过长，无法生成二维码"
  end

  local codewords = buildCodewords(content, version)
  local size = version * 4 + 17

  local best = nil
  for mask = 0, 7 do
    local modules, reserved = newMatrix(size)
    drawFunctionPatterns(modules, reserved, version, size)
    placeCodewords(modules, reserved, codewords, size)
    applyMask(modules, reserved, mask, size)
    drawFormat(modules, mask, size)
    drawVersion(modules, version, size)
    local score = penaltyScore(modules, size)
    if best == nil or score < best.score then
      best = { score = score, modules = modules, mask = mask }
    end
  end

  return {
    size = size,
    modules = best.modules,
    version = version,
    mask = best.mask,
  }
end

-- 供测试与解码校验使用：返回功能图形占位表（true = 功能模块，不参与数据放置）
function M.functionMap(version)
  local size = version * 4 + 17
  local modules, reserved = newMatrix(size)
  drawFunctionPatterns(modules, reserved, version, size)
  return reserved
end

-- 供单元测试使用
M._internal = {
  gfMul = gfMul,
  rsDivisor = rsDivisor,
  rsRemainder = rsRemainder,
  versionInfo = VERSION_INFO,
  alignment = ALIGNMENT,
  formatBits = formatBits,
  maskCondition = maskCondition,
}

return M
