import SwiftUI

struct MiniPlayer: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let current = playback.current {
            HStack(spacing: 12) {
                WorkArtwork(work: current.item, radius: 8)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(current.item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
                Button {
                    playback.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("前进 15 秒")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { router.showsPlayer = true }
            .accessibilityAction(named: "打开播放器") { router.showsPlayer = true }
        }
    }

    private var subtitle: String {
        if let remaining = playback.sleepRemaining {
            return "定时 \(DurationFormat.clock(remaining)) 后停止"
        }
        return playback.current?.track.title ?? ""
    }
}
