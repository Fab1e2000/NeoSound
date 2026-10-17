import SwiftUI

struct AddToPlaylistView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let work: ASMRWork
    @State private var lists: [ASMRPlaylist] = []
    @State private var page = 0
    @State private var hasNext = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            if !store.loggedIn { NavigationLink("登录 ASMR.ONE 后添加作品") { AccountView() } }
            ForEach(lists) { playlist in Button(playlist.name) { Task { await add(playlist) } }.disabled(busy) }
            if hasNext { Button("更多列表") { Task { await load() } }.disabled(busy) }
            if busy { ProgressView() }
            if let error { RetryRow(message:error) { Task { await load() } } }
        }.navigationTitle("加入网站播放列表").toolbar { Button("取消") { dismiss() } }.task { await load() }
    }
    private func load() async {
        guard store.loggedIn else { return }; busy = true; defer { busy = false }
        do { let result = try await store.client.playlists(page:page + 1,filter:"owned"); lists += result.playlists; page = result.pagination.currentPage; hasNext = result.pagination.hasNext; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func add(_ playlist: ASMRPlaylist) async {
        busy = true; defer { busy = false }
        do { try await store.client.mutatePlaylist("add-works-to-playlist",body:["id":playlist.id,"works":[work.id]]); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
