# ASMR.ONE 接入记录

协议来自对公开网站前端源码的调查（2026-10-16），原始证据在 `/Users/elsterlee/Dev/REA/asmr-one-analysis`。

## 网络与认证

- `ASMRClient` 统一构造请求，默认 `https://api.asmr-200.com`；`ASMRStore` 管理会话与设置。
- 搜索关键词作为单个路径段完整 percent-encode，超过 500 字符改用 POST；仅随机排序带 `seed`；保留 `includeTranslationWorks=true`。
- 媒体只使用服务器返回的 HTTPS 地址，不拼签名，不持久化流地址；播放、字幕、封面请求不带 API 的 Bearer。
- 密码不存盘；令牌存 Keychain（ThisDeviceOnly），登录请求不附已有令牌。拒绝跨源重定向。切换 API 线路会退出登录并停止播放。
- 401 / JWT 错误只作用于仍匹配的当前令牌；断网、超时、5xx 保留会话。前台校验成功后 5 分钟内不重复；服务器返回新令牌则保存。

## 使用中的接口

| 功能 | 请求 |
|---|---|
| 作品列表 / 搜索 | GET `/api/works`、GET `/api/search/{keyword}`（长关键词 POST `/api/search/`） |
| 作品信息 / 音轨 | GET `/api/workInfo/{id}`（登录后 `/api/work/{id}`）、GET `/api/tracks/{id}?v=2` |
| 登录 / 会话校验 | POST `/api/auth/me` `{name,password}`；GET `/api/auth/me` |

网站播放列表接口（get-playlists、add-works-to-playlist、create-playlist 等）已调查但不再使用：App 改用本地列表。系统保留列表名为 `__SYS_PLAYLIST_MARKED`（我标记的）、`__SYS_PLAYLIST_LIKED`（我喜欢的）。

## 尚未验收

- 真实账号下的登录回包、令牌长期保持、登录后的写入（目前只有源码契约与本地替身测试）。
- 真机锁屏、蓝牙、AirPlay、中断恢复、长时间后台、睡眠定时精度。
- 流地址过期：目前重进详情页刷新，没有自动续签。
- AVAudioSession 中断 API 在 iOS 27 软弃用，待迁移并真机回归。
