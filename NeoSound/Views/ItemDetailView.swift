import SwiftUI

struct ItemDetailView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(TitleTranslator.self) private var translator
    @Environment(FavoritesStore.self) private var favorites
    @AppStorage("translatesTitles") private var translatesTitles = true
    let item: ASMRWork
    @State private var detail: ASMRWork?
    @State private var contents = WorkContents([])
    @State private var version: TrackVersion?
    @State private var error: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var generation = 0
    @State private var addingTrack: TrackEntry?
    @State private var extras: ExtraKind?
    @State private var showsCover = false
    @AppStorage(ContentFilter.storageKey) private var allowsAdult = false
    private var work: ASMRWork { detail ?? item }
    private var tracks: [TrackEntry] { contents.tracks(for:version) + contents.bonusAudio }
    private var isCurrentWork: Bool { playback.current?.item.id == work.id }

    var body: some View {
        if ContentFilter.allows(work,allowsAdult:allowsAdult) {
            content
        } else {
            ContentUnavailableView("作品不可用",systemImage:"eye.slash",description:Text("该作品为 R18 作品。可在设置中启用 R18 后查看。"))
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                Button { showsCover = true } label: { WorkArtwork(work:work,radius:0,aspectRatio:4.0/3) }
                    .buttonStyle(.plain)
                    .disabled(work.coverURL == nil)
                    .accessibilityLabel("查看封面大图")
                titleBlock.padding(.horizontal,20).padding(.top,18)
                statsCard.padding(.horizontal,16).padding(.top,16)
                actions.padding(.horizontal,16).padding(.top,14)
                trackSection.padding(.top,26)
                if contents.hasExtras { extrasSection.padding(.top,28) }
                infoSection.padding(.top,28)
            }
            .padding(.bottom,40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                ShareLink(item:URL(string:"https://asmr.one/work/\(work.sourceID)")!)
            }
        }
        .sheet(item:$addingTrack) { track in NavigationStack { AddToPlaylistView(track:track,work:work) } }
        .fullScreenCover(isPresented:$showsCover) {
            if let url = work.coverURL { ImageViewer(images:[ViewerImage(id:"cover",url:url,title:work.sourceID)]) }
        }
        .sheet(item:$extras) { kind in NavigationStack { ExtrasList(kind:kind,work:work,entries:entries(for:kind)) } }
        .task(id:store.client.baseURL) { await load() }
        .task(id:translatesTitles) { if translatesTitles { translator.request(work.title) } }
        .refreshable { await load() }
    }

    // MARK: Title and summary

    /// Translated title split into a headline and the ～…～ tagline the site often appends.
    private var titleParts: (main: String, tagline: String?) {
        let title = translator.display(work.title,translated:translatesTitles)
        guard let open = title.firstIndex(where:{ "～〜~".contains($0) }) else { return (title,nil) }
        let main = title[..<open].trimmingCharacters(in:.whitespaces)
        let tagline = title[title.index(after:open)...].trimmingCharacters(in:CharacterSet(charactersIn:"～〜~ "))
        return main.isEmpty ? (title,nil) : (main,tagline.isEmpty ? nil : tagline)
    }

    private var titleBlock: some View {
        VStack(alignment:.leading,spacing:6) {
            let credits = [work.creator,(work.vas ?? []).isEmpty ? nil : "CV " + (work.vas ?? []).map(\.name).joined(separator:"、")].compactMap { $0 }
            if !credits.isEmpty { Text(credits.joined(separator:" · ")).font(.footnote.weight(.semibold)).foregroundStyle(.tint) }
            Text(titleParts.main).font(.title2.bold())
            if let tagline = titleParts.tagline { Text(tagline).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private var totalDuration: Double? {
        let sum = tracks.compactMap(\.duration).reduce(0,+)
        return sum > 0 ? sum : work.duration
    }
    private var statsCard: some View {
        HStack(spacing:0) {
            if let rating = work.rate_average_2dp {
                stat(Label(String(format:"%.2f",rating),systemImage:"star.fill"),caption:work.rate_count.map { "\($0) 条评价" } ?? "评分")
            }
            if let total = totalDuration {
                stat(Text(DurationFormat.clock(total)),caption:"总时长")
            }
            if let downloads = work.dl_count {
                stat(Text("\(downloads)"),caption:"下载")
            }
        }
        .padding(.vertical,12)
        .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:12))
    }
    private func stat(_ value: some View, caption: String) -> some View {
        VStack(spacing:2) {
            value.font(.title3.bold()).labelStyle(StarValueStyle())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity)
    }

    private var actions: some View {
        HStack(spacing:12) {
            Button {
                if isCurrentWork { playback.resume(); router.showsPlayer = true }
                else if let first = tracks.first { play(first) }
            } label: {
                Label(isCurrentWork ? "继续播放" : "播放",systemImage:"play.fill").frame(maxWidth:.infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isCurrentWork && tracks.isEmpty)
            let favorited = favorites.contains(work)
            Button { favorites.toggle(work) } label: {
                Label(favorited ? "已收藏" : "收藏",systemImage:favorited ? "heart.fill" : "heart")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(.bordered)
            .sensoryFeedback(.selection,trigger:favorited)
        }
        .controlSize(.large)
    }

    // MARK: Tracks

    private var trackSection: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Text("曲目").font(.title3.bold())
                Spacer()
                if contents.versions.count > 1 {
                    Text("\(contents.versions.count) 个版本，内容相同").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal,20)
            if contents.versions.count > 1 { versionPickers.padding(.horizontal,20) }
            VStack(spacing:0) {
                if loading && !loaded {
                    ForEach(0..<5,id:\.self) { _ in
                        Text("正在载入曲目…").redacted(reason:.placeholder).frame(maxWidth:.infinity,minHeight:52,alignment:.leading).padding(.horizontal,16)
                    }
                } else if let error {
                    RetryRow(message:error) { Task { await load() } }
                } else if tracks.isEmpty {
                    Text("没有可播放的音轨").foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:52)
                } else {
                    ForEach(Array(tracks.enumerated()),id:\.element.id) { index,entry in
                        trackRow(entry,index:index,last:index == tracks.count - 1)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:12))
            .clipShape(.rect(cornerRadius:12))
            .padding(.horizontal,16)
            if !tracks.isEmpty, let total = totalDuration {
                Text("\(tracks.count) 首 · \(DurationFormat.label(total))").font(.footnote).foregroundStyle(.secondary).padding(.horizontal,32)
            }
        }
    }

    private var versionPickers: some View {
        HStack(spacing:10) {
            if contents.formats.count > 1 {
                Picker("格式",selection:Binding(get:{ version?.format ?? "" },set:{ pick(format:$0,withSE:version?.withSE ?? true) })) {
                    ForEach(contents.formats,id:\.self) { Text($0 == "WAV" || $0 == "FLAC" ? "\($0) 无损" : $0).tag($0) }
                }
            }
            if contents.hasSEChoice {
                Picker("音效",selection:Binding(get:{ version?.withSE ?? true },set:{ pick(format:version?.format ?? "",withSE:$0) })) {
                    Text("含音效").tag(true)
                    Text("无音效").tag(false)
                }
            }
        }
        .pickerStyle(.segmented)
    }
    private func pick(format: String, withSE: Bool) {
        version = contents.resolve(format:format,withSE:withSE) ?? version
    }

    private func trackRow(_ entry: TrackEntry, index: Int, last: Bool) -> some View {
        let parts = WorkContents.display(entry.title)
        let name = translator.display(parts.name,translated:translatesTitles,clean:false)
        let playing = playback.current?.id == entry.id
        return Button { play(entry) } label: {
            HStack(spacing:12) {
                Group {
                    if playing { Image(systemName:"waveform").foregroundStyle(.tint) }
                    else { Text(parts.number ?? "\(index + 1)").foregroundStyle(.secondary) }
                }
                .font(.subheadline.monospacedDigit()).frame(width:26,alignment:.leading)
                VStack(alignment:.leading,spacing:2) {
                    Text(name).foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.vertical,9)
                Text(entry.duration.map(DurationFormat.clock) ?? "--:--").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(minHeight:52)
            .padding(.horizontal,16)
            .background(Color(.secondarySystemGroupedBackground))
            .contentShape(.rect)
            // The long-press preview lifts the row as a rounded card of its own.
            .contentShape(.contextMenuPreview,.rect(cornerRadius:12))
        }
        .buttonStyle(.plain)
        .disabled(entry.node.streamURL == nil)
        .contextMenu {
            Button("加入列表…",systemImage:"text.badge.plus") { addingTrack = entry }
            Section {
                Button("下一首播放",systemImage:"text.line.first.and.arrowtriangle.forward") { playback.playNext(entry,in:work) }
                    .disabled(playback.current == nil)
                Button("加入播放队列",systemImage:"text.line.last.and.arrowtriangle.forward") { playback.enqueue(entry,in:work) }
            }
        }
        .task(id:translatesTitles) { if translatesTitles { translator.request(parts.name,clean:false) } }
    }

    // MARK: Extras

    private func entries(for kind: ExtraKind) -> [TrackEntry] {
        switch kind {
        case .scripts: contents.scripts
        case .images: contents.images
        case .subtitles: contents.subtitles
        case .others: contents.others
        }
    }
    private var extrasSection: some View {
        let kinds = ExtraKind.allCases.filter { !entries(for:$0).isEmpty }
        let count = kinds.map { entries(for:$0).count }.reduce(0,+)
        return VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Text("特典").font(.title3.bold())
                Spacer()
                Text("\(count) 个文件").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal,20)
            LazyVGrid(columns:[GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10)],spacing:10) {
                ForEach(kinds) { kind in
                    Button { extras = kind } label: {
                        VStack(alignment:.leading,spacing:4) {
                            Text(kind.title).font(.subheadline.weight(.semibold))
                            Text(kind.summary(entries(for:kind))).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth:.infinity,minHeight:76,alignment:.leading)
                        .padding(.horizontal,14)
                        .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal,16)
        }
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("作品信息").font(.title3.bold()).padding(.horizontal,20)
            VStack(alignment:.leading,spacing:0) {
                if let circle = work.circle {
                    NavigationLink(value:WorkQuery.circle(circle.name)) { infoRow("社团",circle.name,chevron:true) }.buttonStyle(.plain)
                }
                ForEach(work.vas ?? []) { person in
                    NavigationLink(value:WorkQuery.va(person.name)) { infoRow("声优",person.name,chevron:true) }.buttonStyle(.plain)
                }
                if let release = work.release {
                    infoRow("发售",[release,ageLabel].compactMap { $0 }.joined(separator:" · "))
                }
                let languages = (work.language_editions ?? []).compactMap(\.label)
                if !languages.isEmpty {
                    infoRow("语言",languages.joined(separator:" · "))
                }
                if let tags = work.tags, !tags.isEmpty {
                    VStack(alignment:.leading,spacing:10) {
                        Text("标签").foregroundStyle(.secondary)
                        WorkChipLayout(spacing:8) {
                            ForEach(tags) { tag in
                                NavigationLink(value:WorkQuery.tag(tag.name)) {
                                    Text(tag.name).font(.footnote).padding(.horizontal,12).padding(.vertical,6)
                                        .background(Color(.systemGroupedBackground),in:Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
                if let buckets = work.rate_count_detail, buckets.contains(where:{ ($0.count ?? 0) > 0 }) {
                    ratingDistribution(buckets).padding(16)
                }
                if let source = work.source_url.flatMap(URL.init(string:)), source.scheme == "https" {
                    Link("在 DLsite 查看原页面",destination:source).frame(maxWidth:.infinity,minHeight:48,alignment:.leading).padding(.horizontal,16)
                }
            }
            .background(Color(.secondarySystemGroupedBackground),in:.rect(cornerRadius:12))
            .padding(.horizontal,16)
        }
    }
    private var ageLabel: String? {
        switch work.age_category_string {
        case "general": "全年龄"
        case "r15": "R15"
        default: nil
        }
    }
    private func infoRow(_ label: String, _ value: String, chevron: Bool = false) -> some View {
        HStack(spacing:8) {
            Text(label).foregroundStyle(.secondary).frame(width:56,alignment:.leading)
            Text(value).frame(maxWidth:.infinity,alignment:.leading)
            if chevron { Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .frame(minHeight:48)
        .padding(.horizontal,16)
        .contentShape(.rect)
    }
    private func ratingDistribution(_ buckets: [RatingBucket]) -> some View {
        let total = max(1,buckets.compactMap(\.count).reduce(0,+))
        return VStack(alignment:.leading,spacing:6) {
            Text("评分分布").foregroundStyle(.secondary)
            ForEach((1...5).reversed(),id:\.self) { point in
                let count = buckets.first { $0.review_point == point }?.count ?? 0
                let share = Double(count) / Double(total)
                HStack(spacing:8) {
                    Text("\(point)★").frame(width:26,alignment:.leading)
                    GeometryReader { geometry in
                        Capsule().fill(.quaternary)
                            .overlay(alignment:.leading) { Capsule().fill(.orange).frame(width:geometry.size.width * share) }
                    }
                    .frame(height:6)
                    Text("\(Int((share * 100).rounded()))%").frame(width:36,alignment:.trailing)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Loading and playback

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
            detail = work
            let rebuilt = WorkContents(TrackEntry.flatten(tree,workID:item.id))
            contents = rebuilt
            // Keep the viewer's version choice across refreshes when it still exists.
            if version == nil || !rebuilt.versions.contains(version!) { version = rebuilt.defaultVersion }
            loaded = true
        } catch { if generation == ticket, !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription } }
    }
    private func play(_ track: TrackEntry) { playback.play(track,in:work,tracks:tracks); router.showsPlayer = true }
}

/// Shows a value label with a small orange star in front, as in the rating stat.
private struct StarValueStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing:4) { configuration.icon.font(.subheadline).foregroundStyle(.orange); configuration.title }
    }
}

enum ExtraKind: String, CaseIterable, Identifiable {
    case scripts, images, subtitles, others
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scripts: "台本与说明"
        case .images: "插画"
        case .subtitles: "字幕"
        case .others: "其他文件"
        }
    }
    func summary(_ entries: [TrackEntry]) -> String {
        switch self {
        case .images: "\(entries.count) 张"
        default: "\(entries.count) 份"
        }
    }
}

/// Extra files: audio and subtitles use the player; images and scripts have in-app readers.
struct ExtrasList: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let kind: ExtraKind
    let work: ASMRWork
    let entries: [TrackEntry]
    @State private var viewing: ViewerImage?
    private var viewerImages: [ViewerImage] {
        entries.compactMap { entry in
            (entry.node.mediaStreamUrl ?? entry.node.mediaDownloadUrl).map { ViewerImage(id:entry.id,url:$0,title:entry.title) }
        }
    }
    var body: some View {
        List {
            Group {
                ForEach(folders,id:\.self) { folder in
                    Section(folder) {
                        ForEach(entries.filter { $0.path == folder }) { entry in row(entry) }
                    }
                }
                if kind == .subtitles && playback.current?.item.id != work.id {
                    Text("先播放这部作品，再选择字幕。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item:$viewing) { ImageViewer(images:viewerImages,start:$0.id) }
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
    }
    private var folders: [String] { entries.reduce(into:[]) { if !$0.contains($1.path) { $0.append($1.path) } } }
    @ViewBuilder private func row(_ entry: TrackEntry) -> some View {
        switch kind {
        case .subtitles:
            Button { playback.loadSubtitle(entry); dismiss() } label: { Label(entry.title,systemImage:"captions.bubble") }
                .disabled(playback.current?.item.id != work.id)
        case .scripts:
            if let url = entry.node.mediaStreamUrl ?? entry.node.mediaDownloadUrl {
                NavigationLink { DocumentReader(title:entry.title,url:url) } label: {
                    Label(entry.title,systemImage:"doc.text")
                }
            } else {
                Label(entry.title,systemImage:"doc").foregroundStyle(.secondary)
            }
        case .images:
            if let image = viewerImages.first(where:{ $0.id == entry.id }) {
                Button { viewing = image } label: { Label(entry.title,systemImage:"photo") }
            } else {
                Label(entry.title,systemImage:"photo").foregroundStyle(.secondary)
            }
        default:
            if let url = entry.node.mediaStreamUrl {
                Link(destination:url) { Label(entry.title,systemImage:kind == .images ? "photo" : "doc.text") }
            } else {
                Label(entry.title,systemImage:"doc").foregroundStyle(.secondary)
            }
        }
    }
}
