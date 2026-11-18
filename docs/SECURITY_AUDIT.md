# 安全审计报告

审计范围：原 Web 项目 `html/` 中**仍在使用的**前端代码与接口调用，以及本版本的实现。
已按要求**不审计、不依赖、不恢复**已弃用的 `server.py`。

---

## 一、结论摘要

| 项 | 结论 |
| --- | --- |
| 硬编码密钥 / Token / Secret | **未发现**。原项目与本版本均无明文凭据字面量 |
| 疑似需轮换的凭据 | **无**（见第二节逐项核查） |
| 用户 Token 存储 | 本版本已改为 Keystore AES/GCM 加密，原项目为 localStorage 明文 |
| 密码处理 | 仅用于登录请求，不落盘、不写日志 |
| 日志泄露 | 本版本日志对长串与手机号做遮蔽 |
| 第三方域名收 Token | **存在**（原项目设计），本版本保留但限定为用户主动操作 + 明确风险提示 |
| HTTPS | 全部接口均为 HTTPS |

---

## 二、凭据逐项核查

对原项目全量源码搜索 `token` / `password` / `secret` / `accessKey` / `AccessKeyId` /
`AccessKeySecret` / `ak` / `sk` / `appKey` 等关键字：

| 项 | 位置 | 性质 | 处置 |
| --- | --- | --- | --- |
| OSS `AccessKeyId` / `AccessKeySecret` | `html/doReadGame.js:199,200,207,208` | **运行时变量引用**，来自 `getStsToken` 响应的 `data.AccessKeyId` / `data.AccessKeySecret`，**非字面量** | 无凭据需要轮换。本版本未引入 OSS，相关代码未迁移 |
| OSS 桶名与区域 | `html/doReadGame.js:198,202` | `bucket: 'vanthink'`、`region: 'oss-cn-qingdao'`，非密钥 | 未迁移 |
| STS 下发端点 | `html/doReadGame.js:193` | 第三方 `zxzjapi.930390.xyz:2778/api/tool/upload/getStsToken` | 未迁移 |
| 硬编码业务常量 | `html/doReadGame.js:570,575` | `game_id='26'`、`resource_id='14362982'`，非密钥 | 未迁移 |
| 用户 Token | `html/index_tY4mX2gU.js:2` | `localStorage['token']` **明文** | 本版本改为 Keystore 加密；**建议原 Web 版用户重新登录一次以清除旧 localStorage 残留** |
| 手机号 + 密码 | `html/index_tY4mX2gU.js:88-96` | 经 HTTPS 提交至官方接口，无本地加密、无验证码 | 本版本不存储密码；官方接口未提供验证码流程 |

**结论：未发现需要在服务端轮换的硬编码密钥。** 因此本报告不含"建议撤销/轮换"的具体凭据条目。

---

## 三、本版本凭据存储

### Token

```
AndroidKeyStore (AES-256, GCM, NoPadding)
  └── 密钥别名 vanthink_vault_v1（密钥材料不出 TEE，不可导出）
SharedPreferences
  └── secure.auth_token = "v1:<base64(iv)>:<base64(ciphertext)>"
```

- 实现：`app/storage/secure.lua`
- 运行时**不提供** `EncryptedSharedPreferences`（类不存在，已实测），故自建等价能力。
- 加解密失败时 `getSecret` 返回 `nil`，应用按"未登录"处理，不会崩溃。
- 退出登录调用 `removeSecret` 删除密文（密钥保留以便下次复用）。

### 密码

- 仅在 `auth.login` 调用期间存在于局部变量，随调用结束释放。
- **不写入** SharedPreferences、不写入文件、不进入日志。
- 登录成功后仅保存手机号（`vt_pref_last_phone`）用于下次预填。

### 账号展示信息

`state.account`（昵称 / id / 头像 URL）属非敏感数据，缓存于偏好设置 `account_cache`。

---

## 四、日志安全

`app/utils/logger.lua`：

1. **不使用 `print`**。运行时 `print` 会产生界面级提示，既干扰界面也可能暴露信息给旁人。
   改为写 `android.util.Log`。
2. 输出前用正则把长度 ≥ 24 的连续 `[%w_%-%.]` 串替换为 `前4位***`（覆盖 Token 形态）。
3. 手机号单独提供 `maskPhone()`：`138****8000`。
4. 登录日志只记录 `logger.i("登录成功: " .. logger.maskPhone(phone))`。
5. `debugEnabled` 默认 `false`，发布构建中详细日志不输出。

HTTP 层记录的是 `tag`（如 `homework/list`）、`ok`、`kind`、`errcode`，**不记录** Token 与响应正文。

---

## 五、网络与传输

| 项 | 实现 |
| --- | --- |
| 协议 | 全部 HTTPS（`config.lua` 中无 `http://` 地址） |
| 鉴权头 | `Authorization: <token>`，不进 URL |
| Token 进 URL 的唯一场景 | Auth 迁移 `/create?auth=<token>`（第三方协议设计如此，见第七节） |
| 请求体 | 表单体（table）/ JSON（字符串），由 `http.lua` 统一编码 |
| 错误暴露 | 只向用户展示分类后的可读信息，不展示原始异常堆栈（仅 Logcat） |
| 失败兜底 | 绝不返回伪造数据 |

---

## 六、输入与渲染安全

原 Web 版存在 XSS 风险面（通知内容经 `escapeHtml` 转义，但其他位置用 `innerHTML` 拼接）。
本版本**无 HTML 渲染路径**：所有文本通过 `TextView.setText()` 设置，天然不存在 HTML/JS 注入。

| 项 | 实现 |
| --- | --- |
| 通知正文 | `TextView` 纯文本，无富文本解析 |
| 手机号 | 正则校验 `^1\d{10}$` |
| 耗时输入 | `inputType = "number"` + 范围校验 1~86400 |
| 颜色输入 | 正则 `^[0-9A-Fa-f]{6}$` |
| 迁移链接 | 必须以 `https://` 开头，否则拒绝 |
| 二维码内容 | 由服务端返回的 URL 生成，长度上限由编码器版本 10 约束（超长直接拒绝并提示） |

---

## 七、第三方服务风险评估

本应用访问三个第三方域名（均来自原项目，非本版本新增）：

| 域名 | 用途 | 风险 | 缓解措施 |
| --- | --- | --- | --- |
| `zxzjurl.930390.xyz` | Auth 迁移（生成/状态/领取） | **Token 作为 query 参数发送**，会进入对方访问日志与 Referer 链；二维码 URL 等价于凭据 | ① 仅用户主动点击「Auth 迁移」时调用，不在启动/后台调用；② 界面显著提示"二维码等价于登录凭据，请只在自己的设备上扫描"；③ 一次性有效（服务端 `used` 控制）；④ 页面隐藏即停止轮询；⑤ 失败不影响任何主流程 |
| `zxzjverlog.930390.xyz` | 更新日志 | 低（不传任何用户数据） | 失败静默忽略；不阻塞启动；无自动下载 |
| `zxzjapi.930390.xyz` / `awasr.930390.xyz` | 语音练习（STS/ASR/评分） | 高（STS 凭证下发 + Token 外发） | **未引入**。语音功能未实现，相关依赖全部未迁移 |

### 关于 Token 外发到第三方

这是原项目的协议设计，官方接口未提供等价的 Auth 迁移能力。本版本的处置原则：

- 不做静默调用（原项目也是用户主动触发，本版本保持一致并加强提示）；
- 不因为第三方可用性问题阻塞主功能；
- 在「隐私与安全说明」页明确告知数据流向。

**如需彻底消除该风险**：移除 Auth 迁移功能。当前保留了业务入口以满足"不随意删除有效功能"的要求，
同时以提示方式把风险决定权交给用户。

---

## 八、权限最小化

| 权限 | 用途 | 是否必需 |
| --- | --- | --- |
| `INTERNET` | 全部网络请求 | 必需 |

**未申请**：`CAMERA`（无扫码）、`RECORD_AUDIO`（无语音）、`WRITE_EXTERNAL_STORAGE`
（保存图片走 MediaStore，API 29+ 免权限）、`READ_PHONE_STATE` 等。

---

## 九、保存与分享的数据落盘

| 路径 | 内容 | 清理 |
| --- | --- | --- |
| `Pictures/VanthinkMD3/vanthink_<ts>.png` | 用户主动保存的分享图 | 由用户/相册管理 |
| `Android/media/<包名>/share_<ts>.png` | 系统分享的临时图 | 同名时间戳，未自动清理（建议后续加清理策略） |
| SharedPreferences | Token 密文、账号展示信息、主题偏好 | 退出登录清除 Token 与账号 |

**注意**：`share_<ts>.png` 会随分享次数累积占用空间。已在 `docs/UNIMPLEMENTED.md` 列为待优化项。

---

## 十、残余风险与建议

| # | 风险 | 严重度 | 建议 |
| --- | --- | --- | --- |
| 1 | Auth 迁移把 Token 发给第三方中转 | 中 | 若不接受该风险，应在后续版本移除迁移功能 |
| 2 | 官方接口无验证码/二次验证，密码错误可被暴力尝试 | 中 | 属服务端能力，客户端无法解决；前端已做格式校验避免明显无效请求 |
| 3 | 无 Token 刷新机制，长期不登录需重新输入密码 | 低 | 官方未提供 refresh 接口 |
| 4 | 分享临时图未自动清理 | 低 | 增加启动时清理 7 天前的 `share_*.png` |
| 5 | 账号信息缓存在偏好设置（非敏感但含 id/昵称） | 低 | 可接受；退出登录时已清除 |
| 6 | 未做证书固定（certificate pinning） | 低 | 运行时未暴露自定义 OkHttpClient 入口；如可接入可后续加强 |

---

## 十一、审计方法说明

| 手段 | 说明 |
| --- | --- |
| 原项目源码关键字全量搜索 | `token`/`password`/`secret`/`accessKey`/`ak`/`sk` 等 |
| 运行时类可用性实测 | `luajava.bindClass` 逐一验证 `EncryptedSharedPreferences`、zxing、MLKit、CameraX 是否存在 |
| Keystore 加解密往返实测 | AES/GCM 加密后解密，验证明文一致（见 TEST_REPORT） |
| 运行时可访问性实测 | 对受保护接口分别用「无 token」「错误 token」请求，确认返回 `errcode 44` |
| 代码审查 | 逐文件检查凭据使用、日志输出、URL 构造、输入校验 |
