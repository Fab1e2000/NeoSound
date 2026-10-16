import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    @State private var category: Category?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let items = library.recommended(category: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let current = playback.current {
                    continueCard(current)
                }

                CategoryChips(selection: $category)

                Text("为你推荐")
                    .font(.title2.bold())
                    .padding(.top, 4)

                if items.isEmpty {
                    ContentUnavailableView("这个分类还没有内容", systemImage: "moon.zzz",
                                           description: Text("审核通过的作品会出现在这里。"))
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("首页")
    }

    private func continueCard(_ current: AdmittedTrack) -> some View {
        Button {
            router.showsPlayer = true
        } label: {
            HStack(spacing: 14) {
                ArtworkView(style: current.item.artwork, cornerRadius: 14)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.isPlaying ? "正在播放" : "继续收听")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(current.item.title)
                        .font(.headline)
                    if let duration = playback.duration {
                        Text("还剩 \(DurationFormat.label(max(0, duration - playback.elapsed)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.tint, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .onTapGesture { playback.togglePlayPause() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CategoryChips: View {
    @Binding var selection: Category?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", selected: selection == nil) { selection = nil }
                ForEach(Category.allCases, id: \.self) { category in
                    chip(category.label, selected: selection == category) { selection = category }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(selected ? Color.white : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ItemCard: View {
    @Environment(Library.self) private var library
    let item: CatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(style: item.artwork)
                .frame(height: 120)
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text("\(item.category.label) · \(DurationFormat.label(library.firstPlayable(in: item)?.duration))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, -4)
        }
        .contentShape(Rectangle())
    }
}
