import SwiftUI

struct RootView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerTransition
    var body: some View {
        @Bindable var router = router
        TabView {
            Tab("浏览",systemImage:"square.grid.2x2") {
                NavigationStack { BrowseView().workDestinations() }
            }
            Tab("列表",systemImage:"music.note.list") {
                NavigationStack { PlaylistsView().workDestinations() }
            }
            Tab("设置",systemImage:"gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        // As in NeoDizzy: the tab bar minimizes on scroll and the mini player folds inline beside it.
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled:playback.current != nil) {
            MiniPlayerView(transitionNamespace:playerTransition) { router.showsPlayer = true }
        }
        // The player zooms out of the mini player's artwork and is dismissed by dragging down.
        .fullScreenCover(isPresented:$router.showsPlayer) {
            NowPlayingView()
                .presentationBackground(.clear)
                .presentationContentInteraction(.resizes)
                .navigationTransition(.zoom(sourceID:NowPlayingView.transitionID,in:playerTransition))
        }
        .task(id:scenePhase) {
            if scenePhase == .active { await store.refreshSession() }
        }
        .onChange(of:store.sessionRevision) { playback.stop() }
        .onChange(of:scenePhase) { if scenePhase == .active { playback.updateSleepTimer() } }
        .alert("提示", isPresented:Binding(get:{ store.message != nil || playback.notice != nil },set:{ if !$0 { store.message = nil; playback.notice = nil } })) {
            Button("好") { store.message = nil; playback.notice = nil }
        } message: { Text(store.message ?? playback.notice ?? "") }
    }
}
/// A filtered work list reached from a tag, circle or voice actor.
struct WorkQuery: Hashable {
    let title: String
    let keyword: String
    static func tag(_ name: String) -> WorkQuery { WorkQuery(title:name,keyword:"$tag:\(name)$") }
    static func circle(_ name: String) -> WorkQuery { WorkQuery(title:name,keyword:"$circle:\(name)$") }
    static func va(_ name: String) -> WorkQuery { WorkQuery(title:name,keyword:"$va:\(name)$") }
}
extension View {
    /// All in-stack navigation is value-based; mixing destination-closure links with value links resets pushed pages.
    func workDestinations() -> some View {
        navigationDestination(for:ASMRWork.self) { ItemDetailView(item:$0) }
            .navigationDestination(for:WorkQuery.self) { WorkBrowser(title:$0.title,keyword:$0.keyword) }
            .navigationDestination(for:LibraryRoute.self) { route in
                switch route {
                case .playlist(let id): LocalPlaylistView(id:id)
                }
            }
    }
}
