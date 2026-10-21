import SwiftUI

struct RootView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(SearchHistory.self) private var history
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerTransition
    @State private var tab = RootTab.browse
    @State private var search = SearchModel()
    var body: some View {
        @Bindable var router = router
        TabView(selection:$tab) {
            Tab("浏览",systemImage:"square.grid.2x2",value:.browse) {
                NavigationStack { BrowseView().workDestinations() }
            }
            Tab("列表",systemImage:"music.note.list",value:.library) {
                NavigationStack { PlaylistsView().workDestinations() }
            }
            Tab("设置",systemImage:"gearshape",value:.settings) {
                NavigationStack { SettingsView() }
            }
            Tab("搜索",systemImage:"magnifyingglass",value:.search,role:.search) { SearchTab(model:search) }
        }
        // On the TabView the search field sits in the tab bar; opening the search tab starts typing right away.
        .searchable(text:$search.text,isPresented:$search.isPresented,prompt:"作品、标签、社团、声优")
        .onSubmit(of:.search) { search.open(.keyword(search.query),history:history) }
        .onChange(of:tab) { search.isPresented = tab == .search }
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
        .onChange(of:scenePhase) { if scenePhase == .active { playback.updateSleepTimer() } }
        .alert("提示", isPresented:Binding(get:{ store.message != nil || playback.notice != nil },set:{ if !$0 { store.message = nil; playback.notice = nil } })) {
            Button("好") { store.message = nil; playback.notice = nil }
        } message: { Text(store.message ?? playback.notice ?? "") }
    }
}
enum RootTab: Hashable { case browse, library, settings, search }
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
                case .favoriteWorks: FavoriteWorksView()
                }
            }
    }
}
