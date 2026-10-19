import SwiftUI

/// Favorite works as a two-column cover grid; long-press a work to remove it.
struct FavoriteWorksView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TitleTranslator.self) private var translator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("translatesTitles") private var translatesTitles = true
    @AppStorage("favoritesNewestFirst") private var newestFirst = true

    private var columns: [GridItem] {
        Array(repeating:GridItem(.flexible(),spacing:16,alignment:.top),count:dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }
    private var works: [ASMRWork] { newestFirst ? favorites.works : favorites.works.reversed() }

    var body: some View {
        ScrollView {
            LazyVGrid(columns:columns,alignment:.leading,spacing:18) {
                ForEach(works) { work in
                    NavigationLink(value:work) {
                        VStack(alignment:.leading,spacing:4) {
                            WorkArtwork(work:work,radius:12,aspectRatio:4.0/3).padding(.bottom,4)
                            Text(translator.display(work.title,translated:translatesTitles))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            if let creator = work.creator {
                                Text(creator).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("取消收藏",systemImage:"heart.slash",role:.destructive) { withAnimation { favorites.toggle(work) } }
                    }
                    .task(id:translatesTitles) { if translatesTitles { translator.request(work.title) } }
                }
            }
            .padding(.horizontal,16)
            if let error = favorites.saveError { Text(error).font(.footnote).foregroundStyle(.red).padding(16) }
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if favorites.works.isEmpty {
                ContentUnavailableView("还没有收藏作品",systemImage:"heart",description:Text("在作品详情里点“收藏”。"))
            }
        }
        .navigationTitle("收藏的作品")
        .navigationSubtitle("\(favorites.works.count) 部")
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu("排序",systemImage:"arrow.up.arrow.down") {
                    Picker("排序",selection:$newestFirst) {
                        Text("最近收藏").tag(true)
                        Text("最早收藏").tag(false)
                    }
                }
                .disabled(favorites.works.isEmpty)
            }
        }
    }
}
