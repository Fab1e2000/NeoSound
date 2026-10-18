# NeoSound

ASMR.ONE 的 iOS 在线收听客户端（SwiftUI，iOS 27+）。当前是精简版本，在此基础上逐步扩展功能。

## 功能

- **浏览**：打开即是“浏览”页（网站全部全年龄与 R15 作品），原生大标题、双列网格；顶部横向选择器切换排序、升/降序、含字幕；下拉刷新、滚到底自动翻页。底部标签栏为“浏览”“列表”“设置”。不需要登录，所有请求都是匿名的。
- **卡片标题**：去掉【】、[]、() 及其中文字（全角半角都算）；日语标题默认用 DeepSeek（deepseek-flash，附 ASMR 术语表）译成简体中文，需在设置里填 DeepSeek API Key；译文缓存在本机。RJ 号默认隐藏。两项都可在设置里切换。
- **全年龄过滤**：所有作品查询都附加网站搜索条件 `$-age:adult$`，由服务器排除 18 禁、保留全年龄和 R15；客户端再按 `nsfw` 兜底过滤，详情页同样拦截。
- **作品详情**：4:3 封面、中文标题与原标题、评分/总时长/下载量；曲目按 MP3/WAV、含/无音效自动分成版本，可切换；特典按台本、插画、特典音声、字幕归类；作品信息含社团、声优、标签、语言版本、评分分布、DLsite 链接。
- **播放**：AVPlayer 在线播放。播放页移植自 NeoDizzy（源自 MeloX，GPL-3.0）：封面 / 字幕 / 队列三页、进度、音量、AirPlay、随机与循环、队列拖动排序；更多菜单里有睡眠定时（淡出）和倍速。迷你播放器为系统标签栏胶囊，滚动时收起成一行。
- **我的列表**：本地播放列表，存在 App 的 Application Support/playlists.json；底部“列表”标签进入，作品详情里“加入列表”。可新建、重命名、删除、排序。暂不支持导出。

未包含：离线下载、播放列表管理页、推荐、搜索、注册（跳转网站）、字幕搜索/上传、跨设备进度同步。

## 构建与测试

需要 Xcode 27、XcodeGen。工程由 `project.yml` 生成，增删文件后重新执行 `xcodegen generate`。

```sh
xcodegen generate
xcodebuild -project NeoSound.xcodeproj -scheme NeoSound \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build/DerivedData -collect-test-diagnostics never \
  test CODE_SIGNING_ALLOWED=NO
```

网络层只读在线自检（不下载媒体）：

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  NeoSound/Models/Catalog.swift NeoSound/Models/ASMR.swift NeoSound/Models/ContentFilter.swift \
  NeoSound/Services/ASMRClient.swift Tools/OnlineSmoke.swift -o build/online-smoke
build/online-smoke
```

接口契约与尚未验收的范围见 [Docs/ASMR-INTEGRATION.md](Docs/ASMR-INTEGRATION.md)。
