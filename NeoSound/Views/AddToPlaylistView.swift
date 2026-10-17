import SwiftUI

/// Routes for the on-device playlists.
enum LibraryRoute: Hashable {
    case playlist(UUID)
}

/// Picks which local playlists hold a work; tapping a list adds or removes it.
struct AddToPlaylistView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    let work: ASMRWork
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(playlists.playlists) { playlist in
                    Button { playlists.toggle(work,in:playlist.id) } label: {
                        HStack {
                            VStack(alignment:.leading,spacing:2) {
                                Text(playlist.name).foregroundStyle(.primary)
                                Text("\(playlist.works.count) 部作品").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if playlists.contains(work,in:playlist.id) { Image(systemName:"checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if playlists.playlists.isEmpty {
                    Text("还没有列表，可以在下面新建一个。").foregroundStyle(.secondary)
                }
            } header: { Text("我的列表") } footer: { Text("点一下加入，再点一下移出。列表只保存在这台设备上。") }
            Section("新建") {
                TextField("新列表名称",text:$newName)
                Button("新建并加入") {
                    let playlist = playlists.create(name:newName)
                    playlists.toggle(work,in:playlist.id)
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

/// All local playlists.
struct PlaylistsView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @State private var naming: NamingTarget?
    @State private var name = ""

    private enum NamingTarget: Identifiable, Equatable {
        case create, rename(UUID)
        var id: String { switch self { case .create: "create"; case .rename(let id): id.uuidString } }
    }

    var body: some View {
        List {
            ForEach(playlists.playlists) { playlist in
                NavigationLink(value:LibraryRoute.playlist(playlist.id)) {
                    HStack(spacing:12) {
                        Group {
                            if let first = playlist.works.first { WorkArtwork(work:first,radius:8,aspectRatio:4.0/3) }
                            else {
                                RoundedRectangle(cornerRadius:8).fill(.quaternary).aspectRatio(4.0/3,contentMode:.fit)
                                    .overlay { Image(systemName:"music.note.list").foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width:64)
                        VStack(alignment:.leading,spacing:2) {
                            Text(playlist.name)
                            Text("\(playlist.works.count) 部作品").font(.caption).foregroundStyle(.secondary)
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
        .overlay {
            if playlists.playlists.isEmpty {
                ContentUnavailableView("还没有列表",systemImage:"music.note.list",description:Text("在作品详情里点“加入列表”，或者点右上角新建。"))
            }
        }
        .navigationTitle("我的列表")
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

/// One local playlist: tap a work to open it, swipe to remove, Edit to reorder.
struct LocalPlaylistView: View {
    @Environment(LocalPlaylistStore.self) private var playlists
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true
    let id: UUID

    var body: some View {
        if let playlist = playlists.playlists.first(where:{ $0.id == id }) {
            List {
                ForEach(playlist.works) { work in
                    NavigationLink(value:work) {
                        HStack(spacing:12) {
                            WorkArtwork(work:work,radius:8,aspectRatio:4.0/3).frame(width:80)
                            VStack(alignment:.leading,spacing:3) {
                                Text(translator.display(work.title,translated:translatesTitles)).font(.subheadline).lineLimit(2)
                                if let creator = work.creator { Text(creator).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .task(id:translatesTitles) { if translatesTitles { translator.request(work.title) } }
                }
                .onDelete { playlists.remove(at:$0,from:id) }
                .onMove { playlists.move(from:$0,to:$1,in:id) }
            }
            .overlay {
                if playlist.works.isEmpty {
                    ContentUnavailableView("列表是空的",systemImage:"music.note.list",description:Text("在作品详情里点“加入列表”添加作品。"))
                }
            }
            .navigationTitle(playlist.name)
            .toolbar { if !playlist.works.isEmpty { EditButton() } }
        } else {
            ContentUnavailableView("列表已删除",systemImage:"music.note.list")
        }
    }
}
