import SwiftUI

/// Favorite works: tap to open, swipe to remove, Edit to reorder.
struct FavoriteWorksView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TitleTranslator.self) private var translator
    @AppStorage("translatesTitles") private var translatesTitles = true

    var body: some View {
        List {
            ForEach(favorites.works) { work in
                NavigationLink(value:work) {
                    HStack(spacing:12) {
                        WorkArtwork(work:work,radius:8,aspectRatio:4.0/3).frame(width:80)
                        VStack(alignment:.leading,spacing:3) {
                            Text(translator.display(work.title,translated:translatesTitles)).font(.subheadline).lineLimit(2)
                            if let creator = work.creator { Text(creator).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .swipeActions {
                    Button("取消收藏",systemImage:"heart.slash",role:.destructive) { favorites.toggle(work) }
                }
                .task(id:translatesTitles) { if translatesTitles { translator.request(work.title) } }
            }
            .onMove { favorites.move(from:$0,to:$1) }
            if let error = favorites.saveError { Text(error).foregroundStyle(.red) }
        }
        .overlay {
            if favorites.works.isEmpty {
                ContentUnavailableView("还没有收藏作品",systemImage:"heart",description:Text("在作品详情里点“收藏”。"))
            }
        }
        .navigationTitle("收藏的作品")
        .toolbar { if !favorites.works.isEmpty { EditButton() } }
    }
}
