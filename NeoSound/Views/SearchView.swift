import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                browse
            } else {
                results
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "雨声、白噪音、冥想")
    }

    private var browse: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("浏览分类")
                    .font(.title2.bold())
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Category.allCases, id: \.self) { category in
                        Button {
                            query = category.label
                        } label: {
                            Text(category.label)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 100, alignment: .bottomLeading)
                                .background(category.tileColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var results: some View {
        let matches = library.search(query)
        return List {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                Section("“\(query)”的结果") {
                    ForEach(matches) { item in
                        if library.hasPlayable(item) {
                            NavigationLink(value: item) { ItemRow(item: item) }
                        } else {
                            ItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

/// 列表行。没有可播放音轨的作品显示锁和原因，不提供入口。
struct ItemRow: View {
    @Environment(Library.self) private var library
    let item: CatalogItem

    var body: some View {
        let playable = library.hasPlayable(item)
        HStack(spacing: 12) {
            Group {
                if playable {
                    ArtworkView(style: item.artwork, cornerRadius: 10, symbolScale: 0.45)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .overlay { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(playable ? .primary : .secondary)
                Text(playable ? "\(item.category.label) · \(item.tracks.count) 条音轨" : denialMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var denialMessage: String {
        guard let track = item.tracks.first, case .failure(let denial) = library.evaluate(track, in: item) else {
            return "暂时不能播放"
        }
        return denial.userMessage
    }
}

extension Category {
    var tileColor: Color {
        switch self {
        case .rain: ArtworkStyle.rain.background
        case .noise: ArtworkStyle.noise.background
        case .nature: ArtworkStyle.forest.background
        case .calm: ArtworkStyle.fire.background
        case .breath: ArtworkStyle.breath.background
        }
    }
}
