import SwiftUI

struct ItemDetailView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    let item: ASMRWork
    @State private var detail: ASMRWork?
    @State private var entries: [TrackEntry] = []
    @State private var error: String?
    @State private var loading = false
    @State private var generation = 0
    @State private var showsPlaylist = false
    @State private var showsReview = false
    @State private var section = "files"
    private var work: ASMRWork { detail ?? item }
    private var audios: [TrackEntry] { entries.filter { $0.node.type == "audio" } }
    private var folders: [String] { entries.reduce(into:[]) { if !$0.contains($1.path) { $0.append($1.path) } } }
    var body: some View {
        List {
            Section {
                VStack(spacing:12) {
                    WorkArtwork(work:work,radius:20).frame(width:180,height:180)
                    Text(work.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text([work.sourceID,work.release,work.creator].compactMap { $0 }.joined(separator:" · "))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let rating = work.rate_average_2dp { Label(String(format:"%.2f",rating),systemImage:"star.fill").font(.subheadline) }
                    HStack {
                        Button { if let first = audios.first { play(first) } } label: {
                            Label("播放",systemImage:"play.fill").frame(maxWidth:.infinity)
                        }.buttonStyle(.borderedProminent).disabled(audios.isEmpty)
                        Button { showsPlaylist = true } label: {
                            Label("加入列表",systemImage:"text.badge.plus").frame(maxWidth:.infinity)
                        }.buttonStyle(.bordered)
                    }.controlSize(.large)
                }.frame(maxWidth:.infinity).padding(.vertical,12)
            }.listRowBackground(Color.clear)
            Picker("作品内容",selection:$section) {
                Text("文件目录").tag("files")
                Text("作品信息").tag("info")
            }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
            if section == "info" {
            if let circle = work.circle {
                Section("社团") { NavigationLink(circle.name) { WorkBrowser(title:circle.name,keyword:"$circle:\(circle.name)$") } }
            }
            if let vas = work.vas, !vas.isEmpty {
                Section("声优") { ForEach(vas) { person in NavigationLink(person.name) { WorkBrowser(title:person.name,keyword:"$va:\(person.name)$") } } }
            }
            if let tags = work.tags, !tags.isEmpty {
                Section("标签") {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack { ForEach(tags) { tag in NavigationLink { WorkBrowser(title:tag.name,keyword:"$tag:\(tag.name)$") } label: { Text(tag.name).font(.caption).padding(8).background(.quaternary,in:Capsule()) } } }
                    }
                }
            }
            Section("我的收听记录") {
                Button { showsReview = true } label: { Label("评分、笔记与收听状态",systemImage:"star.bubble") }
            }
            }
            if section == "files" {
            if loading && entries.isEmpty { Section("文件目录") { ForEach(0..<4,id:\.self) { _ in Text("正在载入音轨目录…").redacted(reason:.placeholder) } } }
            if let error { RetryRow(message:error) { Task { await load() } } }
            ForEach(folders,id:\.self) { folder in
                Section(folder.isEmpty ? "文件" : folder) {
                    ForEach(entries.filter { $0.path == folder }) { entry in
                        if entry.node.type == "audio" {
                            Button { play(entry) } label: {
                                HStack {
                                    Image(systemName:playback.current?.id == entry.id ? "waveform" : "play.circle")
                                    Text(entry.title).foregroundStyle(.primary)
                                    Spacer()
                                    Text(entry.duration.map(DurationFormat.clock) ?? "--:--").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }.disabled(entry.node.stream(preferSmall:store.preferSmall) == nil)
                            .contextMenu { Button("加入播放队列") { playback.enqueue(entry,in:work) } }
                        } else if [".vtt",".srt",".lrc"].contains(where:{ entry.title.lowercased().hasSuffix($0) }) {
                            Button { playback.loadSubtitle(entry) } label: { Label(entry.title,systemImage:"captions.bubble") }
                                .disabled(playback.current?.item.id != work.id)
                        } else if let url = entry.node.mediaStreamUrl {
                            Link(destination:url) { Label(entry.title,systemImage:entry.node.type == "image" ? "photo":"doc.text") }
                        } else { Label(entry.title,systemImage:"doc").foregroundStyle(.secondary) }
                    }
                }
            }
            if !loading && entries.isEmpty && error == nil { ContentUnavailableView("暂无音轨",systemImage:"waveform") }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement:.topBarTrailing) {
                Button { showsReview = true } label: { Image(systemName:work.progress == nil ? "heart":"heart.fill") }.accessibilityLabel(work.progress == nil ? "收藏到网站":"管理网站收藏")
                Menu {
                    Button("加入网站播放列表") { showsPlaylist = true }
                    Button("评分与收听状态") { showsReview = true }
                    ShareLink(item:URL(string:"https://asmr.one/work/\(work.sourceID)")!)
                } label: { Image(systemName:"ellipsis") }
            }
        }
        .sheet(isPresented:$showsPlaylist) { NavigationStack { AddToPlaylistView(work:work) } }
        .sheet(isPresented:$showsReview,onDismiss:{ Task { await load() } }) { ReviewEditor(work:work) }
        .task(id:"\(store.sessionRevision)|\(store.loggedIn)") { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        generation += 1; let ticket = generation
        loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            async let metadata = store.client.work(item.id)
            async let nodes = store.client.tracks(item.id)
            let (work,tree) = try await (metadata,nodes)
            try Task.checkCancellation()
            guard generation == ticket else { return }
            detail = work; entries = TrackEntry.flatten(tree,workID:item.id)
        } catch { if generation == ticket, !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription } }
    }
    private func play(_ track: TrackEntry) { playback.play(track,in:work,tracks:audios); router.showsPlayer = true }
}

struct ReviewEditor: View {
    @Environment(ASMRStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let work: ASMRWork
    @State private var rating = 0
    @State private var progress = "marked"
    @State private var text = ""
    @State private var busy = false
    @State private var ready = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if !store.loggedIn { NavigationLink("登录 ASMR.ONE 后保存记录") { AccountView() } }
                Picker("评分",selection:$rating) { Text("未评分").tag(0); ForEach(1...5,id:\.self) { Text("\($0) 星").tag($0) } }
                Picker("收听状态",selection:$progress) {
                    Text("想听").tag("marked"); Text("正在听").tag("listening"); Text("已听完").tag("listened"); Text("重听").tag("replay"); Text("搁置").tag("postponed")
                }
                TextField("笔记 / 评价",text:$text,axis:.vertical).lineLimit(4...10)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("网站收听记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button(busy ? "保存中…":"保存") { Task { await save() } }.disabled(busy || !store.loggedIn || !ready) }
            }
        }.task(id:"\(store.sessionRevision)|\(store.loggedIn)") {
            ready = false
            guard store.loggedIn else { return }
            do {
                let latest = try await store.client.work(work.id)
                try Task.checkCancellation()
                rating = latest.userRating ?? 0
                progress = latest.progress ?? "marked"
                text = latest.review_text ?? ""
                error = nil; ready = true
            } catch {
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            try await store.saveReview(workID:work.id,rating:rating,text:text,progress:progress)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
