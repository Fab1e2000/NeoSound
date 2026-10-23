import SwiftUI

struct RootView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerTransition
    @AppStorage(RootTabSettings.orderKey) private var storedOrder = RootTabSettings.defaultOrder
    @State private var tab = RootTabSettings.launchTab(UserDefaults.standard.string(forKey:RootTabSettings.launchKey))
    @State private var search = SearchModel()
    var body: some View {
        @Bindable var router = router
        TabView(selection:$tab) {
            ForEach(RootTabSettings.order(from:storedOrder)) { destination in
                Tab(destination.title,systemImage:destination.systemImage,value:destination) {
                    NavigationStack {
                        Group {
                            switch destination {
                            case .browse: BrowseView()
                            case .recommend: RecommendView()
                            case .library: PlaylistsView()
                            case .search: EmptyView()
                            }
                        }.workDestinations()
                    }
                }
            }
            Tab("搜索",systemImage:"magnifyingglass",value:.search,role:.search) { SearchTab(model:search) }
        }
        // Opening the search tab starts typing right away.
        .onChange(of:tab,initial:true) { search.isPresented = tab == .search }
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
        // Settings, with the account at the top, open from the avatar on each tab.
        .sheet(isPresented:$router.showsSettings) { SettingsSheet() }
        .task(id:scenePhase) { if scenePhase == .active { await store.refreshSession() } }
        .onChange(of:scenePhase) { if scenePhase == .active { playback.updateSleepTimer(); VersionDownloadStore.shared.validate() } }
        .background { LibraryAutoBackup() }
        .alert("提示", isPresented:Binding(get:{ store.message != nil || playback.notice != nil },set:{ if !$0 { store.message = nil; playback.notice = nil } })) {
            Button("好") { store.message = nil; playback.notice = nil }
        } message: { Text(store.message ?? playback.notice ?? "") }
    }
}
enum RootTab: String, Hashable, CaseIterable, Identifiable {
    case browse, recommend, library, search
    var id: String { rawValue }
    var title: String {
        switch self {
        case .browse: "浏览"
        case .recommend: "推荐"
        case .library: "列表"
        case .search: "搜索"
        }
    }
    var systemImage: String {
        switch self {
        case .browse: "square.grid.2x2"
        case .recommend: "sparkles"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }
}

enum RootTabSettings {
    static let orderKey = "mainTabs.order"
    static let launchKey = "mainTabs.startup"
    static let defaultOrder = "browse,recommend,library"
    static func order(from stored: String) -> [RootTab] {
        var result: [RootTab] = []
        for value in stored.split(separator:",") {
            if let tab = RootTab(rawValue:String(value)), tab != .search, !result.contains(tab) { result.append(tab) }
        }
        return result + [RootTab.browse, .recommend, .library].filter { !result.contains($0) }
    }
    static func launchTab(_ stored: String?) -> RootTab {
        stored.flatMap(RootTab.init(rawValue:)) ?? .browse
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
                case .favoriteWorks: FavoriteWorksView()
                case .downloads: DownloadsView()
                }
            }
    }
}
