# NeoSound

ASMR.ONE 的 iOS 在线收听客户端（SwiftUI，iOS 27+）。当前是精简版本，在此基础上逐步扩展功能。

## 功能

- **浏览**：打开即是“健全”标签作品，双列网格；排序、含字幕筛选、下拉刷新、滚到底自动翻页。无底部标签栏，账号与设置在顶部工具栏。
- **作品详情**：信息、封面、音轨目录、附带文件；标签/社团/声优可跳转关联作品；字幕文件手动选择（VTT/SRT/LRC）。
- **播放**：AVPlayer 在线播放、迷你播放器、完整播放器、队列、循环/打乱、倍速、音质选择、系统媒体控制、睡眠定时淡出。
- **账号**：登录/退出，令牌存 Keychain，启动恢复与前台校验；断网保留会话，明确认证失效才退出。登录后可在详情页评分、写笔记、设收听状态，以及把作品加入自己的网站播放列表。

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

网络层只读在线自检（不登录、不写账号、不下载媒体）：

```sh
xcrun swiftc -parse-as-library -default-isolation MainActor \
  NeoSound/Models/Catalog.swift NeoSound/Models/ASMR.swift \
  NeoSound/Services/ASMRClient.swift Tools/OnlineSmoke.swift -o build/online-smoke
build/online-smoke
```

接口契约与尚未验收的范围见 [Docs/ASMR-INTEGRATION.md](Docs/ASMR-INTEGRATION.md)。
