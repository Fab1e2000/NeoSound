import AVKit
import MediaPlayer
import SwiftUI

struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var showsTimer = false
    @State private var scrubValue: TimeInterval = 0

    var body: some View {
        Group {
            if let current = playback.current {
                content(current)
                    .background(current.item.artwork.playerBackground.ignoresSafeArea())
            } else if case .failed(let message) = playback.phase {
                ContentUnavailableView("无法播放", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView()
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsTimer) { SleepTimerSheet() }
        .onChange(of: playback.phase) {
            if playback.phase == .idle { dismiss() }
        }
    }

    private func content(_ current: AdmittedTrack) -> some View {
        VStack(spacing: 22) {
            artwork(current)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.track.title)
                        .font(.title3.weight(.semibold))
                    Text(current.item.title)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    library.toggleFavorite(current.item)
                } label: {
                    Image(systemName: library.isFavorite(current.item) ? "heart.fill" : "heart")
                        .frame(width: 24, height: 24)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(library.isFavorite(current.item) ? "取消收藏" : "收藏")
            }

            progress

            if case .failed(let message) = playback.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            transport

            VolumeSlider()
                .frame(height: 34)

            bottomBar
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func artwork(_ current: AdmittedTrack) -> some View {
        ArtworkView(style: current.item.artwork, cornerRadius: 22, symbolScale: 0.34)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let cue = playback.activeCue {
                    Text(cue)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .padding(12)
                        .transition(.opacity)
                        .id(cue)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 30, y: 20)
            .scaleEffect(playback.isPlaying ? 1 : 0.86)
            .animation(.spring(duration: 0.45, bounce: 0.25), value: playback.isPlaying)
            .animation(.easeInOut(duration: 0.4), value: playback.activeCue)
    }

    private var progress: some View {
        let upper = max(playback.duration ?? 1, 1)
        let shown = playback.isScrubbing ? scrubValue : playback.elapsed
        return VStack(spacing: 6) {
            Slider(
                value: Binding(get: { min(shown, upper) }, set: { scrubValue = $0 }),
                in: 0...upper
            ) { editing in
                if editing {
                    scrubValue = playback.elapsed
                    playback.isScrubbing = true
                } else {
                    playback.seek(to: scrubValue)
                    playback.isScrubbing = false
                }
            }
            .disabled(playback.duration == nil)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(DurationFormat.clock(shown))，共 \(DurationFormat.clock(upper))")

            HStack {
                Text(DurationFormat.clock(shown))
                Spacer()
                Text(playback.duration.map { "-" + DurationFormat.clock(max(0, $0 - shown)) } ?? "--:--")
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button { playback.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 30))
            }
            .accessibilityLabel("后退 15 秒")
            .frame(maxWidth: .infinity)

            Button { playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .frame(width: 64, height: 64)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
            .frame(maxWidth: .infinity)

            Button { playback.skip(by: 15) } label: {
                Image(systemName: "goforward.15").font(.system(size: 30))
            }
            .accessibilityLabel("前进 15 秒")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                playback.subtitlesEnabled.toggle()
            } label: {
                Image(systemName: playback.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                    .foregroundStyle(playback.subtitlesEnabled && playback.hasSubtitles ? Color.orange : Color.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!playback.hasSubtitles)
            .accessibilityLabel("字幕")
            .accessibilityAddTraits(playback.subtitlesEnabled ? .isSelected : [])
            .frame(maxWidth: .infinity)

            Button { showsTimer = true } label: {
                Label(sleepLabel, systemImage: playback.sleepMode == .off ? "moon.zzz" : "moon.zzz.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(playback.sleepMode == .off ? Color.white : Color.orange)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("睡眠定时")
            .frame(maxWidth: .infinity)

            RoutePicker()
                .frame(width: 44, height: 44)
                .accessibilityLabel("播放输出")
                .frame(maxWidth: .infinity)
        }
    }

    private var sleepLabel: String {
        switch playback.sleepMode {
        case .off: "定时"
        case .minutes, .endOfTrack: playback.sleepRemaining.map(DurationFormat.clock) ?? "定时"
        }
    }
}

/// 系统音量滑杆。
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// AirPlay / 蓝牙输出选择。
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.activeTintColor = .systemOrange
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
