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
        .navigationTitle("加入列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
    }
}

/// The Lists tab: favorite works pinned on top, then all local playlists.
struct PlaylistsView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(FavoritesStore.self) private var favorites
    @State private var naming: NamingTarget?
    @State private var name = ""

    private enum NamingTarget: Identifiable, Equatable {
        case create, rename(UUID)
        var id: String { switch self { case .create: "create"; case .rename(let id): id.uuidString } }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value:LibraryRoute.favoriteWorks) {
                    HStack(spacing:12) {
                        Image(systemName:"heart.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width:36,height:36)
                            .background(.tint,in:.rect(cornerRadius:8))
                        Text("收藏的作品")
                        Spacer()
                        Text("\(favorites.works.count) 部").foregroundStyle(.secondary)
                    }
                }
            }
            Section("我的列表") {
                if playlists.playlists.isEmpty {
                    Text("还没有列表。在作品详情里长按音轨选“加入列表…”，或者点右上角新建。").foregroundStyle(.secondary)
                }
                ForEach(playlists.playlists) { playlist in
                    NavigationLink(value:LibraryRoute.playlist(playlist.id)) {
                        HStack(spacing:12) {
                            Group {
                                if let first = playlist.tracks.first { WorkArtwork(work:first.work,radius:8,aspectRatio:1) }
                                else {
                                    RoundedRectangle(cornerRadius:8).fill(.quaternary).aspectRatio(1,contentMode:.fit)
                                        .overlay { Image(systemName:"music.note.list").foregroundStyle(.secondary) }
                                }
                            }
                            .frame(width:48)
                            VStack(alignment:.leading,spacing:2) {
                                Text(playlist.name)
                                Text(PlaylistSummary.text(playlist.tracks)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("重命名",systemImage:"pencil") { name = playlist.name; naming = .rename(playlist.id) }
                        Button("删除列表",systemImage:"trash",role:.destructive) { playlists.delete(playlist.id) }
                    }
                }
                .onDelete { offsets in offsets.map { playlists.playlists[$0].id }.forEach(playlists.delete) }
            }
        }
        .navigationTitle("列表")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button("新建列表",systemImage:"plus") { name = ""; naming = .create }
            }
        }
        .alert(naming == .create ? "新建列表" : "重命名列表",isPresented:Binding(get:{ naming != nil },set:{ if !$0 { naming = nil } })) {
            TextField("列表名称",text:$name)
            Button("取消",role:.cancel) { naming = nil }
            Button("好") {
                switch naming {
                case .create: playlists.create(name:name)
                case .rename(let id): playlists.rename(id,to:name)
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
    @State private var resolving: String?
    @State private var openedWork: ASMRWork?
    let id: UUID

    var body: some View {
        if let playlist = playlists.playlists.first(where:{ $0.id == id }) {
            List {
                if !playlist.tracks.isEmpty {
                    Section {
                        HStack(spacing:12) {
                            Button { start(playlist.tracks[0],in:playlist.tracks) } label: {
                                Label("播放",systemImage:"play.fill").frame(maxWidth:.infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Button { start(playlist.tracks.randomElement()!,in:playlist.tracks,shuffled:true) } label: {
                                Label("随机播放",systemImage:"shuffle").frame(maxWidth:.infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.large)
                        .disabled(resolving != nil)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } footer: { Text(PlaylistSummary.text(playlist.tracks)) }
                }
                Section {
                    ForEach(playlist.tracks) { track in
                        row(track,in:playlist.tracks)
                            .contextMenu {
                                Button("打开作品",systemImage:"square.stack") { openedWork = track.work }
                            }
                    }
                    .onDelete { playlists.remove(at:$0,from:id) }
                    .onMove { playlists.move(from:$0,to:$1,in:id) }
                }
            }
            .overlay {
                if playlist.tracks.isEmpty {
                    ContentUnavailableView("列表是空的",systemImage:"music.note.list",description:Text("在作品详情里长按音轨，选“加入列表…”。"))
                }
            }
            .navigationTitle(playlist.name)
            .navigationDestination(item:$openedWork) { ItemDetailView(item:$0) }
            .toolbar { if !playlist.tracks.isEmpty { EditButton() } }
        } else {
            ContentUnavailableView("列表已删除",systemImage:"music.note.list")
        }
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
