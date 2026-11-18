-- 敏感数据安全存储：Android Keystore (AES/GCM) + SharedPreferences 密文。
-- 运行时不提供 EncryptedSharedPreferences，因此在此实现等价能力：
-- 密钥保存在 AndroidKeyStore（不出 TEE），偏好设置中只保存 iv 与密文。

local pref = require "app.storage.preferences"

local M = {}

local KEY_ALIAS = "vanthink_vault_v1"
local PREFIX = "secure."

local cachedKey = nil

local function classes()
  return {
    KeyStore = luajava.bindClass("java.security.KeyStore"),
    KeyGenerator = luajava.bindClass("javax.crypto.KeyGenerator"),
    KeyGenParameterSpec = luajava.bindClass("android.security.keystore.KeyGenParameterSpec"),
    Cipher = luajava.bindClass("javax.crypto.Cipher"),
    GCMParameterSpec = luajava.bindClass("javax.crypto.spec.GCMParameterSpec"),
    Base64 = luajava.bindClass("android.util.Base64"),
    JavaString = luajava.bindClass("java.lang.String"),
  }
end

local function ensureKey()
  if cachedKey ~= nil then return cachedKey end
  local c = classes()
  local store = c.KeyStore.getInstance("AndroidKeyStore")
  store.load(nil)
  if not store.containsAlias(KEY_ALIAS) then
    -- PURPOSE_ENCRYPT | PURPOSE_DECRYPT = 1 | 2 = 3
    local builder = c.KeyGenParameterSpec.Builder(KEY_ALIAS, 3)
    builder.setBlockModes({ "GCM" })
    builder.setEncryptionPaddings({ "NoPadding" })
    local generator = c.KeyGenerator.getInstance("AES", "AndroidKeyStore")
    generator.init(builder.build())
    generator.generateKey()
  end
  cachedKey = store.getKey(KEY_ALIAS, nil)
  return cachedKey
end

function M.isAvailable()
  local ok = pcall(ensureKey)
  return ok
end

-- 写入密文；返回 true 表示成功
function M.setSecret(name, plaintext)
  local ok, result = pcall(function()
    local c = classes()
    local key = ensureKey()
    local cipher = c.Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(c.Cipher.ENCRYPT_MODE, key)
    local cipherText = cipher.doFinal(c.JavaString(tostring(plaintext)).getBytes("UTF-8"))
    local iv = cipher.getIV()
    local payload = "v1:"
      .. c.Base64.encodeToString(iv, c.Base64.NO_WRAP) .. ":"
      .. c.Base64.encodeToString(cipherText, c.Base64.NO_WRAP)
    return pref.setString(PREFIX .. name, payload)
  end)
  if not ok then return false end
  return result == true
end

function M.getSecret(name)
  local payload = pref.getString(PREFIX .. name, nil)
  if payload == nil then return nil end
  local ok, result = pcall(function()
    local c = classes()
    local key = ensureKey()
    local ivB64, dataB64 = string.match(payload, "^v1:([^:]+):([^:]+)$")
    if ivB64 == nil then return nil end
    local cipher = c.Cipher.getInstance("AES/GCM/NoPadding")
    local spec = c.GCMParameterSpec(128, c.Base64.decode(ivB64, c.Base64.NO_WRAP))
    cipher.init(c.Cipher.DECRYPT_MODE, key, spec)
    local plain = cipher.doFinal(c.Base64.decode(dataB64, c.Base64.NO_WRAP))
    return tostring(c.JavaString(plain))
  end)
  if not ok then return nil end
  return result
end

function M.removeSecret(name)
  pref.remove(PREFIX .. name)
end

function M.hasSecret(name)
  return pref.getString(PREFIX .. name, nil) ~= nil
end

return M
