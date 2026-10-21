# NeoSound

ASMR.ONE 的 iOS 在线收听客户端（SwiftUI，iOS 27+）。当前是精简版本，在此基础上逐步扩展功能。

## 功能

- **浏览**：打开即是“浏览”页（网站全部全年龄与 R15 作品），原生大标题、双列网格；顶部横向选择器切换排序、升/降序、含字幕；下拉刷新、滚到底自动翻页。底部标签栏为“浏览”“推荐”“列表”，右侧另有独立的搜索按钮；各页右上角的头像打开设置。浏览不需要登录。
- **卡片标题**：去掉【】、[]、() 及其中文字（全角半角都算）；日语标题默认用 DeepSeek（deepseek-flash，附 ASMR 术语表）译成简体中文，需在设置里填 DeepSeek API Key；译文缓存在本机。RJ 号默认隐藏。两项都可在设置里切换。
- **全年龄过滤与 R18 开关**：默认所有作品查询（浏览、搜索、联想、推荐）都附加网站搜索条件 `$-age:adult$`，由服务器排除 18 禁、保留全年龄和 R15；客户端再按 `nsfw` 兜底过滤，详情页同样拦截。设置 › 内容 › 显示 R18 作品（默认关闭，打开时需确认已满 18 岁）打开后不做任何过滤，热门标签和全部标签也改用网站全部标签（白名单外的标签另分为外貌与身体、服装与道具、关系与情境、玩法、癖好、作品类型，网站以后新增的标签暂归“其他”）。
- **作品详情**：4:3 封面、翻译标题（无译文时显示原文）、评分/总时长/下载量；曲目按 MP3/WAV、含/无音效自动分成版本，可切换；特典音声排在曲目末尾，可连续播放；特典按台本、插画、字幕归类；台本/说明支持应用内文本阅读（UTF-8、UTF-16、Shift-JIS）与 PDF 预览；作品信息含社团、声优、标签、语言版本、评分分布、DLsite 链接。
- **播放**：AVPlayer 在线播放。播放页移植自 NeoDizzy（源自 MeloX，GPL-3.0）：封面 / 字幕 / 队列三页、进度、音量、AirPlay、随机与循环、队列拖动排序；更多菜单里有睡眠定时（淡出）和倍速。播放时自动匹配同名或唯一曲目编号的字幕，在字幕页随播放进度高亮滚动；也可在详情页手动选择。未加载到有效字幕时隐藏字幕按钮，AirPlay 与队列自动补位。迷你播放器为系统标签栏胶囊，滚动时收起成一行。
- **搜索**：系统搜索标签（iOS 26 起搜索栏在底部）。未输入时显示最近搜索（最多 10 条，可单条删除或清除，存在 UserDefaults）和热门标签；热门标签只取内置的全年龄标签白名单，按网站 `/api/tags/` 的作品数排序（网站标签表混有 18 禁标签）；标题旁“全部”进入“全部标签”页，按声音与形式、情感与氛围、角色、题材分组，显示作品数，可筛选、按作品数或名称排序。输入时联想：搜索全部作品、匹配的最近搜索与标签、结果中出现的社团/声优，以及前 3 部作品；回车或点选后进入带排序筛选的作品列表。
- **收藏**：作品详情的“收藏”按钮收藏作品，“列表”标签网格里的“收藏的作品”以封面网格查看，长按取消收藏，可按收藏时间正序/倒序。存在 Application Support/favorite-works.json。
- **我的列表**：“列表”标签为双列方形卡片网格（歌单封面取前四部作品拼成），本地音轨歌单，可放不同作品的音轨，按顺序播放；在作品详情里长按音轨选“加入列表…”（同一菜单还有“下一首播放”“加入播放队列”）。歌单里可播放、随机播放，点某一首从那里开始播；可新建、重命名、删除、左滑移除、编辑排序。播放地址会过期，所以只保存作品和音轨标识，播放时重新获取。存在 Application Support/track-playlists.json。
- **备份与导出**：设置 › 资料库。自动备份（每天/每周/关闭，默认每天）在 App 打开或进入后台时写入「文件 › 我的 iPhone › NeoSound › Backup › NeoSound-资料库.json」，含收藏、我的列表、搜索记录、标题译文和设置，可选带上 DeepSeek API Key 与 ASMR.ONE 登录；重装前把 Backup 文件夹拷出，放回后点「导入备份」合并（只添加不删除）。重装后发现未导入的旧备份时暂停自动备份以免覆盖。「导出资料库」生成不含 API Key 和登录信息的同格式文件，经分享菜单保存或发送。参考 NeoDizzy 的实现。
- **账号**：右上角头像 › 账号，用 ASMR.ONE 用户名和密码登录（POST `/api/auth/me`）；令牌存本机钥匙串，只随 API 请求发送，封面和音频请求不带。打开 App 时每 5 分钟内最多校验一次会话，断网或服务器出错不退出，令牌失效才退出并提示。令牌只在签发它的线路有效，切换线路会退出登录。右上角是系统玻璃样式的账号按钮（参照 NeoDizzy 的设置按钮），登录后人像图标变为实心。
- **推荐**：独立标签页，与浏览页同样的双列网格、下拉刷新、自动翻页。登录后为网站的「为你推荐」（POST `/api/recommender/recommend-for-user`，用账号的 recommenderUuid）；未登录显示热门作品（`/api/recommender/popular`）和登录提示。两者都带 `$-age:adult$`，热门作品只有前 100 部，过滤后所剩不多。

未包含：离线下载、注册（跳转网站）、字幕搜索/上传、跨设备进度同步。

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
