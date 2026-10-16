import SwiftUI

struct ItemDetailView: View {
    @Environment(Library.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router
    let item: CatalogItem

    var body: some View {
        let firstPlayable = library.firstPlayable(in: item)
        ScrollView {
            VStack(spacing: 18) {
                ArtworkView(style: item.artwork, cornerRadius: 28)
                    .frame(width: 240, height: 240)
                    .shadow(color: item.artwork.background.opacity(0.5), radius: 30, y: 16)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.title2.bold())
                    if let creator = item.creator {
                        Text(creator)
                            .font(.body)
                            .foregroundStyle(.tint)
                    }
                    Text(metaLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Button {
                    guard let firstPlayable else { return }
                    play(firstPlayable)
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(firstPlayable == nil)

                if firstPlayable == nil, let reason = denialMessage {
                    Label(reason, systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 0) {
                    ForEach(Array(item.tracks.enumerated()), id: \.element.id) { index, track in
                        if index > 0 { Divider().padding(.leading, 48) }
                        TrackRow(index: index + 1, track: track, item: item) { play(track) }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(item)
                } label: {
                    Image(systemName: library.isFavorite(item) ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(library.isFavorite(item) ? "取消收藏" : "收藏")
            }
        }
    }

    private var metaLine: String {
        "\(item.category.label) · \(item.tracks.count) 条音轨 · 共 \(DurationFormat.label(item.totalDuration))"
    }

    private var denialMessage: String? {
        guard let track = item.tracks.first, case .failure(let denial) = library.evaluate(track, in: item) else { return nil }
        return denial.userMessage
    }

    private func play(_ track: Track) {
        playback.play(track, in: item)
        router.showsPlayer = true
    }
}

struct TrackRow: View {
    @Environment(Library.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    let index: Int
    let track: Track
    let item: CatalogItem
    let action: () -> Void

    var body: some View {
        let result = library.evaluate(track, in: item)
        let playable = (try? result.get()) != nil
        let isCurrent = playback.current?.track.id == track.id

        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: playback.isPlaying)
                            .foregroundStyle(.tint)
                    } else {
                        Text("\(index)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .foregroundStyle(playable ? .primary : .secondary)
                    if case .failure(let denial) = result {
                        Label(denial.userMessage, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    } else if !track.subtitles.isEmpty {
                        Text("中文字幕")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(track.duration.map(DurationFormat.clock) ?? "--:--")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .accessibilityHint(playable ? "" : "暂时不能播放")
    }
}
