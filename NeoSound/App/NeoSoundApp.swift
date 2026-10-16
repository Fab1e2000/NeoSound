import SwiftUI

@main
struct NeoSoundApp: App {
    @State private var library: Library
    @State private var playback: PlaybackCoordinator
    @State private var router = AppRouter()

    init() {
        let library = Library()
        library.loadBundledFixtures()
        let playback = PlaybackCoordinator(library: library)
        playback.artworkProvider = { ArtworkView.renderImage($0) }
        _library = State(initialValue: library)
        _playback = State(initialValue: playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(playback)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}

@Observable
final class AppRouter {
    var showsPlayer = false
}
