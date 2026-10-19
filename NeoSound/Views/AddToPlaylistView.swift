import SwiftUI

/// Routes for the on-device playlists.
enum LibraryRoute: Hashable {
    case playlist(UUID)
    case favoriteWorks
}

/// Picks which local playlists hold a track; tapping a list adds or removes it.
struct AddToPlaylistView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(TitleTranslator.self) private var translator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("translatesTitles") private var translatesTitles = true
    let track: TrackEntry
    let work: ASMRWork
    @State private var newName = ""

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(playlists.playlists) { playlist in
                        Button { playlists.toggle(track,of:work,in:playlist.id) } label: {
                            HStack {
                                VStack(alignment:.leading,spacing:2) {
                                    Text(playlist.name).foregroundStyle(.primary)
                                    Text("\(playlist.tracks.count) 首").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if playlists.contains(track,in:playlist.id) { Image(systemName:"checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    if playlists.playlists.isEmpty {
                        Text("还没有列表，可以在下面新建一个。").foregroundStyle(.secondary)
                    }
                } header: {
                    Text(translator.display(WorkContents.display(track.title).name,translated:translatesTitles,clean:false))
                } footer: { Text("点一下加入，再点一下移出。列表只保存在这台设备上。") }
                Section("新建") {
                    TextField("新列表名称",text:$newName)
                    Button("新建并加入") {
                        let playlist = playlists.create(name:newName)
                        playlists.toggle(track,of:work,in:playlist.id)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in:.whitespaces).isEmpty)
                }
                if let error = playlists.saveError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
        .navigationTitle("加入列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
    }
}

/// The Lists tab: favorite works and every playlist as square cards in one two-column grid.
struct PlaylistsView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var naming: PlaylistNaming?

    private var columns: [GridItem] {
        Array(repeating:GridItem(.flexible(),spacing:16,alignment:.top),count:dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns:columns,alignment:.leading,spacing:18) {
                NavigationLink(value:LibraryRoute.favoriteWorks) {
                    PlaylistCard(title:"收藏的作品",caption:"\(favorites.works.count) 部") {
                        Rectangle().fill(.tint).overlay {
                            Image(systemName:"heart.fill").font(.system(size:48,weight:.semibold)).foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                ForEach(playlists.playlists) { playlist in
                    NavigationLink(value:LibraryRoute.playlist(playlist.id)) {
                        PlaylistCard(title:playlist.name,caption:PlaylistSummary.text(playlist.tracks)) {
                            PlaylistCover(tracks:playlist.tracks)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("重命名",systemImage:"pencil") { naming = .rename(playlist.id,playlist.name) }
                        Button("删除列表",systemImage:"trash",role:.destructive) { playlists.delete(playlist.id) }
                    }
                }
            }
            .padding(.horizontal,16)
            if playlists.playlists.isEmpty {
                Text("在作品详情里长按音轨，选“加入列表…”，或者点右上角新建列表。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal,16).padding(.top,8)
                    .frame(maxWidth:.infinity,alignment:.leading)
            }
            if let error = playlists.saveError ?? favorites.saveError {
                Text(error).font(.footnote).foregroundStyle(.red).padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("列表")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button("新建列表",systemImage:"plus") { naming = .create }
            }
        }
        .playlistNamingAlert($naming)
    }
}

/// A square cover with the name and a caption under it, as in the Lists grid.
private struct PlaylistCard<Cover: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let cover: Cover
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Color.clear.aspectRatio(1,contentMode:.fit)
                .overlay { cover }
                .clipShape(.rect(cornerRadius:12))
                .padding(.bottom,4)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children:.combine)
    }
}

/// A playlist's cover: four works' covers in a 2×2 mosaic, else the first work's cover.
struct PlaylistCover: View {
    let tracks: [PlaylistTrack]
    private var works: [ASMRWork] {
        tracks.reduce(into:[ASMRWork]()) { if !$0.contains($1.work) { $0.append($1.work) } }
    }
    var body: some View {
        let works = works
        if works.count >= 4 {
            Grid(horizontalSpacing:1,verticalSpacing:1) {
                GridRow { tile(works[0]); tile(works[1]) }
                GridRow { tile(works[2]); tile(works[3]) }
            }
            .background(.background)
        } else if let first = works.first {
            tile(first)
        } else {
            Rectangle().fill(.quaternary).overlay {
                Image(systemName:"music.note.list").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }
    private func tile(_ work: ASMRWork) -> some View {
        Color.clear.overlay {
            AsyncImage(url:work.coverURL) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
        }
        .clipped()
    }
}

/// Create or rename, shared by the Lists grid and a playlist's own page.
enum PlaylistNaming: Identifiable, Equatable {
    case create, rename(UUID,String)
    var id: String { switch self { case .create: "create"; case .rename(let id,_): id.uuidString } }
}

extension View {
    func playlistNamingAlert(_ naming: Binding<PlaylistNaming?>) -> some View {
        modifier(PlaylistNamingAlert(naming:naming))
    }
}

private struct PlaylistNamingAlert: ViewModifier {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Binding var naming: PlaylistNaming?
    @State private var name = ""
    func body(content: Content) -> some View {
        content
            .onChange(of:naming) { if case .rename(_,let current) = naming { name = current } else { name = "" } }
            .alert(naming == .create ? "新建列表" : "重命名列表",isPresented:Binding(get:{ naming != nil },set:{ if !$0 { naming = nil } })) {
                TextField("列表名称",text:$name)
                Button("取消",role:.cancel) { naming = nil }
                Button("好") {
                    switch naming {
                    case .create: playlists.create(name:name)
                    case .rename(let id,_): playlists.rename(id,to:name)
                    case nil: break
                    }
                    naming = nil
                }
            }
    }
}

nonisolated enum PlaylistSummary {
    /// "3 首 · 1小时2分" style caption; the total is left out when any track's length is unknown.
    static func text(_ tracks: [PlaylistTrack]) -> String {
        let durations = tracks.compactMap(\.duration)
        guard !tracks.isEmpty, durations.count == tracks.count else { return "\(tracks.count) 首" }
        return "\(tracks.count) 首 · " + DurationFormat.label(durations.reduce(0,+))
    }
}

/// One local playlist: tap a track to play the list from there, swipe to remove, Edit to reorder.
struct LocalPlaylistView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true
    @Environment(\.dismiss) private var dismiss
    @State private var resolving: String?
    @State private var openedWork: ASMRWork?
    @State private var naming: PlaylistNaming?
    @State private var editMode: EditMode = .inactive
    let id: UUID

    var body: some View {
        if let playlist = playlists.playlists.first(where:{ $0.id == id }) {
            List {
                Group {
                    Section { header(playlist) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    Section {
                        ForEach(playlist.tracks) { track in
                            row(track,in:playlist.tracks)
                                .contextMenu {
                                    Button("打开作品",systemImage:"square.stack") { openedWork = track.work }
                                }
                        }
                        .onDelete { playlists.remove(at:$0,from:id) }
                        .onMove { playlists.move(from:$0,to:$1,in:id) }
                    } footer: {
                        if playlist.tracks.isEmpty { Text("在作品详情里长按音轨，选“加入列表…”。") }
                    }
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden)
            }
            .environment(\.editMode,$editMode)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item:$openedWork) { ItemDetailView(item:$0) }
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    if editMode.isEditing {
                        Button("完成",systemImage:"checkmark") { withAnimation { editMode = .inactive } }
                    } else {
                        Menu("更多",systemImage:"ellipsis") {
                            Button("重命名",systemImage:"pencil") { naming = .rename(id,playlist.name) }
                            Button("编辑",systemImage:"list.bullet") { withAnimation { editMode = .active } }
                                .disabled(playlist.tracks.isEmpty)
                            Button("删除列表",systemImage:"trash",role:.destructive) { dismiss(); playlists.delete(id) }
                        }
                    }
                }
            }
            .playlistNamingAlert($naming)
        } else {
            ContentUnavailableView("列表已删除",systemImage:"music.note.list")
        }
    }

    private func header(_ playlist: LocalPlaylist) -> some View {
        VStack(spacing:4) {
            PlaylistCover(tracks:playlist.tracks)
                .frame(width:200,height:200)
                .clipShape(.rect(cornerRadius:14))
                .shadow(color:.black.opacity(0.16),radius:14,y:8)
                .padding(.bottom,12)
            Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
            Text(PlaylistSummary.text(playlist.tracks)).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing:12) {
                Button { start(playlist.tracks[0],in:playlist.tracks) } label: {
                    Label("播放",systemImage:"play.fill").frame(maxWidth:.infinity)
                }
                Button { start(playlist.tracks.randomElement()!,in:playlist.tracks,shuffled:true) } label: {
                    Label("随机播放",systemImage:"shuffle").frame(maxWidth:.infinity)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(playlist.tracks.isEmpty || resolving != nil)
            .padding(.top,12)
        }
        .frame(maxWidth:.infinity)
        .padding(.bottom,4)
    }

    private func row(_ track: PlaylistTrack, in list: [PlaylistTrack]) -> some View {
        let name = WorkContents.display(track.title).name
        let playing = playback.current?.id == track.id
        return Button { start(track,in:list) } label: {
            HStack(spacing:12) {
                WorkArtwork(work:track.work,radius:6,aspectRatio:1).frame(width:48)
                VStack(alignment:.leading,spacing:2) {
                    Text(translator.display(name,translated:translatesTitles,clean:false))
                        .foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)).lineLimit(2)
                    Text(translator.display(track.work.title,translated:translatesTitles))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                if resolving == track.id { ProgressView() }
                else if playing { Image(systemName:"waveform").foregroundStyle(.tint).symbolEffect(.variableColor.iterative,isActive:playback.isPlaying) }
                else if let duration = track.duration {
                    Text(DurationFormat.clock(duration)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(resolving != nil)
        .task(id:translatesTitles) {
            if translatesTitles { translator.request(name,clean:false); translator.request(track.work.title) }
        }
    }

    private func start(_ track: PlaylistTrack, in list: [PlaylistTrack], shuffled: Bool = false) {
        resolving = track.id
        Task {
            defer { resolving = nil }
            if let message = await playback.play(track,from:list) { store.message = message; return }
            if shuffled != playback.isShuffled { playback.toggleShuffle() }
            router.showsPlayer = true
        }
    }
}
