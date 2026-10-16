import SwiftUI

enum AppTab: Hashable {
    case home, favorites, library, search
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home

    var body: some View {
        @Bindable var router = router
        TabView(selection: $tab) {
            Tab("首页", systemImage: "house", value: AppTab.home) {
                NavigationStack { HomeView().itemDestinations() }
            }
            Tab("收藏", systemImage: "heart", value: AppTab.favorites) {
                NavigationStack { FavoritesView().itemDestinations() }
            }
            Tab("资料库", systemImage: "square.stack", value: AppTab.library) {
                NavigationStack { LibraryView().itemDestinations() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().itemDestinations() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: playback.current != nil) {
            MiniPlayer()
        }
        .sheet(isPresented: $router.showsPlayer) {
            PlayerView()
        }
        .onChange(of: library.allowlistRevision) {
            playback.revalidate()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { playback.updateSleepTimer() }
        }
        .alert("播放已停止", isPresented: Binding(
            get: { playback.notice != nil },
            set: { if !$0 { playback.notice = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(playback.notice ?? "")
        }
    }
}

extension View {
    func itemDestinations() -> some View {
        navigationDestination(for: CatalogItem.self) { ItemDetailView(item: $0) }
    }
}
