# 第三方来源

## NeoDizzy 与 MeloX

- https://github.com/Fab1e2000/NeoDizzy
- https://github.com/youshen2/MeloX
- 许可证：GNU GPL v3.0（全文见 LICENSE）。
- `NeoSound/Views/NowPlaying/` 及其歌词、背景和转场组件通过 NeoDizzy 移植或直接移植自 MeloX；相关文件保留来源注释，上游参考提交为 `b8bc60f`。
- NeoSound 修改了数据适配、ASMR 字幕、播放队列、下载与缓存集成。上游作者的权利和许可声明继续有效。

## 流式缓存设计参考

`AudioPlaybackCache` 和 `ProgressiveAudioLoader` 移植并适配 NeoDizzy 的缓存实现，其架构参考 https://github.com/neekeetab/CachingPlayerItem （MIT）。NeoSound 增加长音轨范围读取、缓存转下载及多播放项保护；不将架构参考声明解释为第三方媒体授权。

## NeoBili

https://github.com/Fab1e2000/NeoBili （MIT，同一维护者）。README 排版与标签页设置交互参考该项目，NeoSound 的许可证仍为 GPL v3.0。

## 第三方内容

运行时取得的音频、封面、字幕、作品名称和商标归各自权利人所有，不属于本项目软件许可证的授权范围。
