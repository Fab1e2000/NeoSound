# ASMR.ONE 接入记录

协议来自对公开网站前端源码的调查（2026-10-16），原始证据在 `/Users/elsterlee/Dev/REA/asmr-one-analysis`。

## 网络

- `ASMRClient` 统一构造请求，默认 `https://api.asmr-200.com`；`ASMRStore` 管理线路设置与提示消息。
- 搜索关键词作为单个路径段完整 percent-encode，超过 500 字符改用 POST；仅随机排序带 `seed`；保留 `includeTranslationWorks=true`。
- 媒体只使用服务器返回的 HTTPS 地址，不拼签名，不持久化流地址；播放、字幕、封面使用普通请求。
- 所有请求都是匿名的，App 不登录、不携带令牌（账号功能已移除，启动时会清掉旧版本留在 Keychain 的令牌）。拒绝跨源重定向。

## 年龄分级筛选

网站没有单独的分级接口，分级是搜索语法的一部分（前端源码的快捷选项与 2026-10-18 实测一致）：`$age:general$` 仅全年龄（5919 部）、`$age:r15$` 仅 R15（1128）、`$-age:adult$` 全年龄 + R15（7047）、`$age:adult$` 仅 18 禁。可与其他条件用空格组合，如 `$tag:健全$ $-age:adult$`（“健全”标签共 1083 部，其中 53 部是 18 禁）。App 的所有作品查询都附加 `$-age:adult$`。

## 使用中的接口

| 功能 | 请求 |
|---|---|
| 作品列表 / 搜索 | GET `/api/works`、GET `/api/search/{keyword}`（长关键词 POST `/api/search/`） |
| 作品信息 / 音轨 | GET `/api/workInfo/{id}`、GET `/api/tracks/{id}?v=2` |

网站播放列表接口（get-playlists、add-works-to-playlist、create-playlist 等）已调查但不再使用：App 改用本地列表。系统保留列表名为 `__SYS_PLAYLIST_MARKED`（我标记的）、`__SYS_PLAYLIST_LIKED`（我喜欢的）。

## 尚未验收

- 真机锁屏、蓝牙、AirPlay、中断恢复、长时间后台、睡眠定时精度。
- 流地址过期：目前重进详情页刷新，没有自动续签。
- AVAudioSession 中断 API 在 iOS 27 软弃用，待迁移并真机回归。
