import SwiftUI

struct DownloadMark: View {
    let workID: Int
    var body: some View {
        if VersionDownloadStore.shared.hasCompleteVersion(workID) {
            Image(systemName:"arrow.down.circle.fill")
                .font(.system(size:12,weight:.semibold)).foregroundStyle(.primary)
                .padding(.horizontal,6).frame(minWidth:24,minHeight:24)
                .background(.ultraThinMaterial,in:Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.08),lineWidth:0.5) }
                .padding(6).accessibilityLabel("已下载完整版本")
        }
    }
}

struct VersionDownloadButton: View {
    let work: ASMRWork
    let version: TrackVersion?
    let tracks: [TrackEntry]
    let entries: [TrackEntry]
    private var downloads: VersionDownloadStore { .shared }
    private var job: VersionDownload? { version.flatMap { downloads.job(workID:work.id,version:$0) } }
    private var title: String {
        guard let job else { return "下载" }
        if job.isComplete { return "已下载" }
        if job.paused { return "已暂停" }
        if job.files.contains(where:{ $0.state == .downloading || $0.state == .queued }) { return "下载中" }
        return "重试"
    }
    var body: some View {
        Group {
            if job != nil {
                NavigationLink(value:LibraryRoute.downloads) { label }
            } else {
                Button {
                    if let version { downloads.enqueue(work:work,version:version,tracks:tracks,allEntries:entries) }
                } label: { label }
                .disabled(version == nil || tracks.isEmpty)
            }
        }
        .accessibilityLabel(job == nil ? "下载当前版本" : "\(title)，查看下载")
    }
    private var label: some View {
        Label(title,systemImage:job?.isComplete == true ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.subheadline).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth:.infinity)
    }
}

struct DownloadsView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage(ContentFilter.storageKey) private var allowsAdult = false
    @State private var deleting: VersionDownload?
    private var store: VersionDownloadStore { .shared }
    var body: some View {
        List {
            if let issue = store.issue { Text(issue).foregroundStyle(.red) }
            ForEach(store.downloads.filter { ContentFilter.allows($0.work,allowsAdult:allowsAdult) }) { job in
                Section {
                    NavigationLink(value:job.work) {
                        HStack(spacing:12) {
                            WorkArtwork(work:job.work,radius:8,aspectRatio:4.0/3).frame(width:88)
                            VStack(alignment:.leading,spacing:5) {
                                Text(translator.display(job.work.title,translated:translatesTitles)).lineLimit(2)
                                Text(job.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    DownloadJobProgress(job:job)
                    HStack {
                        if job.paused || job.files.contains(where: { $0.state == .failed }) {
                            Button(job.paused ? "继续下载" : "重试失败项") { store.retry(job.id) }
                        }
                        if !job.paused && job.files.contains(where: { $0.state == .queued || $0.state == .downloading }) {
                            Button("暂停下载") { store.pause(job.id) }
                        }
                        Spacer()
                        Button("删除",role:.destructive) { deleting = job }
                    }.buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("下载的作品")
        .overlay {
            if store.downloads.isEmpty { ContentUnavailableView("还没有下载作品",systemImage:"arrow.down.circle",description:Text("在作品详情里选择版本，点“下载”。完整缓存会自动转存。")) }
        }
        .onAppear { store.validate() }
        .confirmationDialog("删除这个版本的下载？",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } }),titleVisibility:.visible) {
            Button("删除下载",role:.destructive) {
                if let job = deleting {
                    if playback.current?.item.id == job.work.id { playback.stop() }
                    store.remove(job.id)
                }
                deleting = nil
            }
        } message: { Text("会删除该版本的音频和附件，收藏和列表保留。") }
    }
}

private struct DownloadJobProgress: View {
    let job: VersionDownload
    private var store: VersionDownloadStore { .shared }
    private var transferring: Bool { !job.paused && job.files.contains { $0.state == .downloading } }
    var body: some View {
        TimelineView(.animation(minimumInterval:1,paused:!transferring)) { _ in
            let status = store.transferSummary(for:job)
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Text(job.paused ? "已暂停" : job.files.allSatisfy { $0.state == .completed } ? "下载完成" : "已保存 \(job.finishedCount)/\(job.audio.count) 首")
                    Spacer()
                    if let fraction = status.fraction { Text(fraction,format:.percent.precision(.fractionLength(1))) }
                }.font(.subheadline).monospacedDigit()
                if let fraction = status.fraction { ProgressView(value:fraction) }
                else if transferring { ProgressView().frame(maxWidth:.infinity,alignment:.leading) }
                HStack {
                    Text(status.total.map { "\(size(status.received)) / \(size($0))" } ?? "已下载 \(size(status.received)) · 总大小未知")
                    Spacer()
                    if transferring { Text("\(size(Int64(status.bytesPerSecond)))/s") }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                ForEach(job.files.filter { $0.state == .failed }) { file in
                    Text(file.track.title + "：" + (file.failure ?? "下载失败")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)
    }
}
