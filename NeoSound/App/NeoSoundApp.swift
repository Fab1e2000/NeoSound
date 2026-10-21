import SwiftUI

@main
struct NeoSoundApp: App {
    @State private var store: ASMRStore
    @State private var playback: PlaybackCoordinator
    @State private var router = AppRouter()
    @State private var playlists = LocalPlaylistStore()
    @State private var favorites = FavoritesStore()
    @State private var searchHistory = SearchHistory()
    @State private var libraryBackup = LibraryBackup()
    @State private var translator: TitleTranslator
    @AppStorage("appearance") private var appearance = "system"
    init() {
        ASMRStore.removeRetiredLoginToken()
        let store = ASMRStore()
        _store = State(initialValue: store)
        let playback = PlaybackCoordinator(store: store)
        let translator = TitleTranslator()
        // The player shows the same translated names as the detail page, honoring the settings switch.
        playback.displayName = { text, isTrack in
            let translates = UserDefaults.standard.object(forKey: "translatesTitles") as? Bool ?? true
            return translator.display(text, translated: translates, clean: !isTrack)
        }
        _playback = State(initialValue: playback)
        _translator = State(initialValue: translator)
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(playback).environment(router).environment(translator).environment(playlists).environment(favorites).environment(searchHistory).environment(libraryBackup)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil).tint(.orange)
        }
    }
}
@Observable
final class AppRouter { var showsPlayer = false; var showsSettings = false }
