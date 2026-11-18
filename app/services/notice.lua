-- 通知服务：列表、单条已读、批量已读。
-- 接口依据原项目实际调用：
--   POST /api/notice/getNoticeList        { type=notice, page, page_size }
--   POST /api/notice/student/doReadNotice { notice_id_array = "[1,2]" }
-- 注意：服务端无“通知详情”接口，列表正文即全文。

local config = require "app.config"
local http = require "app.services.http"

local M = {}

function M.fetchList(opts, callback)
  local page = opts.page or 1
  local pageSize = opts.pageSize or config.NOTICE_PAGE_SIZE
  return http.request({
    url = config.API.noticeList,
    method = "POST",
    form = {
      type = "notice",
      page = page,
      page_size = pageSize,
    },
    auth = true,
    tag = "notice/list",
  }, function(result)
    if not result.ok then
      callback(false, result.message or "通知加载失败", result)
      return
    end
    local data = result.data or {}
    local list = {}
    if type(data.list) == "table" then
      for index, item in ipairs(data.list) do
        list[index] = item
      end
    end
    local count = tonumber(data.count) or #list
    local unread = 0
    for _, item in ipairs(list) do
      local hasRead = item.has_read
      if hasRead == nil or hasRead == 0 or hasRead == false or hasRead == "0" then
        unread = unread + 1
      end
    end
    callback(true, {
      list = list,
      count = count,
      page = page,
      unreadInPage = unread,
      hasMore = #list > 0 and (#list == pageSize) and (#list < count or count == 0),
    }, result)
  end)
end

-- ids 为数字/字符串数组
function M.markRead(ids, callback)
  local payload = {}
  for _, id in ipairs(ids or {}) do
    payload[#payload + 1] = id
  end
  if #payload == 0 then
    if callback then callback(false, "没有需要标记的通知") end
    return nil
  end
  return http.request({
    url = config.API.noticeRead,
    method = "POST",
    form = { notice_id_array = json.encode(payload) },
    auth = true,
    tag = "notice/read",
  }, function(result)
    if not result.ok then
      if callback then callback(false, result.message or "标记已读失败", result) end
      return
    end
    if callback then callback(true, result) end
  end)
end

function M.isUnread(item)
  if type(item) ~= "table" then return false end
  local hasRead = item.has_read
  if hasRead == nil then return true end
  if hasRead == 0 or hasRead == "0" or hasRead == false then return true end
  return false
end

return M
