import SwiftUI

struct RootView: View {
    @Environment(ASMRStore.self) private var store
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        AppSection { BrowseView() }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if playback.current != nil {
                MiniPlayer()
                    .frame(minHeight:56)
                    .background(.regularMaterial,in:.rect(cornerRadius:18))
                    .padding(.horizontal,12)
                    .padding(.vertical,8)
            }
        }
        .sheet(isPresented:$router.showsPlayer) { PlayerView().preferredColorScheme(.dark) }
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
    }
}

private enum AppSheet: String, Identifiable {
    case account, settings
    var id: String { rawValue }
}

/// Main navigation and account/settings actions.
private struct AppSection<Content: View>: View {
    @Environment(ASMRStore.self) private var store
    @State private var sheet: AppSheet?
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack {
            content()
                .workDestinations()
                .toolbar {
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button { sheet = .account } label: { Image(systemName:store.loggedIn ? "person.crop.circle.fill":"person.crop.circle") }
                            .accessibilityLabel("账号")
                        Button { sheet = .settings } label: { Image(systemName:"gearshape") }
                            .accessibilityLabel("设置")
                    }
                }
        }
        .sheet(item:$sheet) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .account: AccountView()
                    case .settings: SettingsView()
                    }
                }
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { sheet = nil } } }
            }
        }
    }
}
