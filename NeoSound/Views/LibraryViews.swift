import SwiftUI

struct FavoritesView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if library.favorites.isEmpty {
                ContentUnavailableView("还没有收藏", systemImage: "heart",
                                       description: Text("在作品页点右上角的心形就能收藏。"))
            } else {
                List(library.favorites) { item in
                    if library.hasPlayable(item) {
                        NavigationLink(value: item) { ItemRow(item: item) }
                    } else {
                        ItemRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("收藏")
    }
}

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        List {
            Section("全部作品") {
                ForEach(library.items) { item in
                    if library.hasPlayable(item) {
                        NavigationLink(value: item) { ItemRow(item: item) }
                    } else {
                        ItemRow(item: item)
                    }
                }
            }

            Section {
                Button("模拟撤销正在播放的音轨", role: .destructive) {
                    if let id = playback.current?.track.id { library.simulateRevocation(of: id) }
                }
                .disabled(playback.current == nil)
                Button("恢复白名单") {
                    library.restoreAllowlist()
                }
                .disabled(library.revokedCount == 0)
            } header: {
                Text("测试工具")
            } footer: {
                Text("白名单版本 \(library.allowlist?.version ?? 0)，已撤销 \(library.revokedCount) 条。用来测试播放中被撤销时会不会马上停止。")
            }

            Section("关于") {
                LabeledContent("版本", value: "\(Bundle.main.shortVersion) 测试版")
                LabeledContent("内容来源", value: "自有合成测试音频")
            }
        }
        .navigationTitle("资料库")
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
}
