-- 分享服务：GET /api/common/share/commonShare?share_id&share_type=homework_student
-- 服务端返回已合成的图片 URL（原项目不做本地合成），
-- 本应用负责下载、展示、保存到相册与调用系统分享面板。

local config = require "app.config"
local http = require "app.services.http"
local logger = require "app.utils.logger"

local M = {}

function M.fetchShareImage(homeworkId, callback)
  return http.request({
    url = config.API.shareImage,
    method = "GET",
    query = {
      { "share_id", homeworkId },
      { "share_type", "homework_student" },
    },
    auth = true,
    tag = "share/image",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "分享图片获取失败", result)
      return
    end
    local data = result.data or {}
    local url = data.share_image
    if url == nil or tostring(url) == "" then
      callback(false, "该作业暂无分享图片", result)
      return
    end
    callback(true, tostring(url), result)
  end)
end

-- 在后台线程下载图片为 Bitmap，成功后回到主线程回调
function M.downloadBitmap(url, callback)
  return xTask {
    dispatcher = "io",
    task = function()
      local ok, bitmap = pcall(function()
        return activity.syncLoadBitmap(url)
      end)
      if not ok or bitmap == nil then
        logger.w("分享图片下载失败: " .. tostring(url))
        return nil
      end
      return bitmap
    end,
    callback = function(bitmap)
      callback(bitmap)
    end,
  }
end

-- 保存到系统相册（MediaStore，Android 10+ 无需存储权限）
-- 返回 ok, message
function M.saveToGallery(bitmap)
  if bitmap == nil then return false, "图片为空" end
  local ok, result = pcall(function()
    local ContentValues = luajava.bindClass("android.content.ContentValues")
    local MediaStore = luajava.bindClass("android.provider.MediaStore")
    local Bitmap = luajava.bindClass("android.graphics.Bitmap")
    local Uri = luajava.bindClass("android.net.Uri")

    local resolver = activity.getContentResolver()
    local values = ContentValues()
    local fileName = string.format("vanthink_%d.png", os.time())
    values.put("_display_name", fileName)
    values.put("mime_type", "image/png")
    values.put("relative_path", "Pictures/VanthinkMD3")

    local collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    local uri = resolver.insert(collection, values)
    if uri == nil then
      return false, "无法在相册中创建文件"
    end
    local stream = resolver.openOutputStream(uri)
    if stream == nil then
      return false, "无法写入相册"
    end
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    stream.flush()
    stream.close()
    return true, "已保存到相册 Pictures/VanthinkMD3/" .. fileName
  end)
  if not ok then return false, tostring(result) end
  return result, result == true and nil or result
end

-- 系统分享面板
function M.shareBitmap(bitmap)
  if bitmap == nil then return false, "图片为空" end
  local ok, result = pcall(function()
    local File = luajava.bindClass("java.io.File")
    local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
    local Intent = luajava.bindClass("android.content.Intent")
    local Bitmap = luajava.bindClass("android.graphics.Bitmap")

    local dir = activity.getMediaDir()
    local file = File(dir, string.format("share_%d.png", os.time()))
    local stream = FileOutputStream(file)
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    stream.flush()
    stream.close()

    local uri = activity.getUriForPath(file.getAbsolutePath())
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("image/png")
    intent.putExtra(Intent.EXTRA_STREAM, uri)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    activity.startActivity(Intent.createChooser(intent, "分享作业图片"))
    return true
  end)
  if not ok then return false, tostring(result) end
  return true
end

return M
