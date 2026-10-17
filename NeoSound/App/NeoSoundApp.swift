import SwiftUI

@main
struct NeoSoundApp: App {
    @State private var store: ASMRStore
    @State private var playback: PlaybackCoordinator
    @State private var router = AppRouter()
    @AppStorage("appearance") private var appearance = "system"
    init() {
        let store = ASMRStore()
        _store = State(initialValue: store)
        _playback = State(initialValue: PlaybackCoordinator(store: store))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(playback).environment(router)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil).tint(.orange)
        }
    }
}
@Observable
final class AppRouter { var showsPlayer = false }
