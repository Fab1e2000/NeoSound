import SwiftUI

/// Settings' "缓存" section: listened audio, with its capacity, and the shared cache for covers and work info.
struct CacheSettingsSection: View {
    @Environment(ASMRStore.self) private var store
    @State private var cache = AudioPlaybackCache.shared
    @State private var networkBytes = URLCache.shared.currentDiskUsage
    @State private var confirmsClear = false
    var body: some View {
        @Bindable var cache = cache
        Section {
            Picker(selection:$cache.capacityGB) {
                ForEach(AudioPlaybackCache.capacityChoices,id:\.self) { Text($0 == 0 ? "关闭" : "\($0) GB").tag($0) }
            } label: { Label("音频缓存上限",systemImage:"waveform") }
            LabeledContent {
                Text(ByteCountFormatter.string(fromByteCount:cache.bytes,countStyle:.file))
            } label: { Label("已缓存音频",systemImage:"internaldrive") }
            LabeledContent {
                Text(ByteCountFormatter.string(fromByteCount:Int64(networkBytes),countStyle:.file))
            } label: { Label("封面与作品信息",systemImage:"photo.on.rectangle") }
            Button(role:.destructive) { confirmsClear = true } label: { Label("清理缓存",systemImage:"trash") }
            if let issue = cache.issue { Text(issue).foregroundStyle(.secondary) }
        } header: { Text("缓存") } footer: {
            Text("听过的完整音轨自动保存，再次播放时不用联网；超过上限时先清理最久未播放的。听到 90% 以上再切走，剩下的部分会在后台下载完。封面和作品信息按服务器允许的时间保存在本机。缓存可能被系统在空间不足时清理。")
        }
        .confirmationDialog("清理缓存？",isPresented:$confirmsClear,titleVisibility:.visible) {
            Button("清理音频、封面和作品信息",role:.destructive) {
                cache.clear(); URLCache.shared.removeAllCachedResponses(); store.clearRecentWorks()
                networkBytes = URLCache.shared.currentDiskUsage
            }
            Button("取消",role:.cancel) {}
        } message: {
            Text("正在播放的音轨会在切换后释放。已下载的作品、收藏、列表和资料库备份不受影响。")
        }
        .onAppear { networkBytes = URLCache.shared.currentDiskUsage }
    }
}
