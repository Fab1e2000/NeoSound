// Adapters that let the Now Playing UI ported from NeoDizzy (itself a MeloX GPL-3.0 port) run on NeoSound's playback.
import SwiftUI
import UIKit

typealias PlayerStore = PlaybackCoordinator

nonisolated enum RepeatMode: String, CaseIterable, Codable, Sendable {
    case off
    case all
    case one

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .off: String(localized: "不循环")
        case .all: String(localized: "列表循环")
        case .one: String(localized: "单曲循环")
        }
    }

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// The ported player's view of one queue item: track name as title, voice actors as artists, the work as album.
nonisolated struct Track: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let artists: String
    let albumTitle: String
    let coverURL: URL?
    var duration: TimeInterval?
}

nonisolated struct UpcomingTrack: Identifiable, Sendable {
    let index: Int
    let track: Track
    var id: Int { index }
}


extension PlaybackCoordinator {
    var currentTrack: Track? { current.map(track(for:)) }
    /// Track and work names go through `displayName`, which the app wires to the title translator.
    func track(for item: PlayingTrack) -> Track {
        let voices = (item.item.vas ?? []).map(\.name)
        return Track(
            id: item.id,
            title: displayName(WorkContents.display(item.track.title).name, true),
            artists: voices.isEmpty ? (item.item.creator ?? item.item.sourceID) : voices.joined(separator: "、"),
            albumTitle: displayName(item.item.title, false),
            coverURL: item.item.coverURL,
            duration: item.track.duration
        )
    }
    var progress: TimeInterval { elapsed }
    var playbackDuration: TimeInterval { duration ?? current?.track.duration ?? 0 }
    var isLoading: Bool { phase == .resolving || phase == .preparing || phase == .buffering }
    var issue: String? { if case .failed(let message) = phase { message } else { nil } }
    var isPreview: Bool { false }
    var isDiscovery: Bool { false }
    var queueModeBadgeSystemImage: String? {
        if isShuffled { return "shuffle" }
        return repeatMode == .off ? nil : repeatMode.systemImage
    }
    func togglePlayback() { togglePlayPause() }
}

nonisolated struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

nonisolated struct LocalLyrics: Equatable, Sendable {
    var lines: [LyricLine]
    var plainText: String
    var source: String = ""
    var isTimed: Bool { !lines.isEmpty }
    var isEmpty: Bool { lines.isEmpty && plainText.isEmpty }

    func activeLine(at time: TimeInterval) -> Int? {
        // Upper bound also handles repeated timestamps deterministically.
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= time { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? lines[low - 1].id : nil
    }

    static func parse(_ text: String) -> LocalLyrics {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#, options: .caseInsensitive)
        let fullRange = NSRange(text.startIndex..., in: text)
        let offset = offsetPattern.firstMatch(in: text, range: fullRange)
            .flatMap { Range($0.range(at: 1), in: text) }.flatMap { Double(text[$0]) }.map { $0 / 1000 } ?? 0
        var timed: [(Double, String, Int)] = []
        var plain: [String] = []
        for raw in text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines) {
            let row = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = timestamp.matches(in: row, range: NSRange(row.startIndex..., in: row))
            if let last = matches.last, let end = Range(last.range, in: row)?.upperBound {
                let words = String(row[end...]).trimmingCharacters(in: .whitespaces)
                for match in matches {
                    func capture(_ n: Int) -> String {
                        Range(match.range(at: n), in: row).map { String(row[$0]) } ?? ""
                    }
                    let minutes = Double(capture(1)) ?? 0
                    let seconds = Double(capture(2)) ?? 0
                    let fraction = Double("0." + capture(3)) ?? 0
                    timed.append((max(0, minutes * 60 + seconds + fraction + offset), words, timed.count))
                }
            } else if !row.isEmpty && row.range(of: #"^\[(ar|ti|al|by|offset|length|re|ve):.*\]$"#, options: [.regularExpression, .caseInsensitive]) == nil {
                plain.append(row)
            }
        }
        timed.sort { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }
        // Original and translated lines at the same timestamp are displayed together.
        var grouped: [(Double, String)] = []
        for (time, words, _) in timed {
            if grouped.last?.0 == time {
                if !words.isEmpty { grouped[grouped.count - 1].1 += "\n" + words }
            } else { grouped.append((time, words)) }
        }
        return LocalLyrics(lines: grouped.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) },
                           plainText: plain.joined(separator: "\n"))
    }
}


/// Cover art for the player, sized by its container.
struct ArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var aspectRatio: CGFloat = 1
    var decodeSize: CGSize? = nil
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        if phase.error != nil || url == nil {
                            Image(systemName: "waveform").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

/// Subtitle cues loaded for the current track, shown on the lyrics page.
@Observable final class NowPlayingLyricsModel {
    private(set) var lyrics: LocalLyrics?
    private(set) var error: String?
    private(set) var revision = 0
    func load(player: PlayerStore) async {
        error = nil
        lyrics = player.subtitleLyrics ?? LocalLyrics(lines: [], plainText: "")
    }
}

/// The "…" menu on the song header: sleep timer, playback speed and subtitles.
struct NowPlayingSongActions: View {
    @Environment(PlayerStore.self) private var player
    @State private var showsSleepTimer = false
    let track: Track
    var onImportLyrics: (() -> Void)? = nil

    var body: some View {
        NowPlayingMenuButton {
            var items: [UIMenuElement] = [
                UIAction(title: sleepTitle, image: UIImage(systemName: player.sleepMode == .off ? "moon.zzz" : "moon.zzz.fill")) { _ in showsSleepTimer = true },
                UIMenu(title: "播放速度", image: UIImage(systemName: "gauge.with.dots.needle.67percent"), children: [0.75, 1.0, 1.25, 1.5, 2.0].map { rate in
                    UIAction(title: "\(rate.formatted())×", state: abs(Double(player.playbackRate) - rate) < 0.01 ? .on : .off) { _ in player.playbackRate = Float(rate) }
                })
            ]
            if player.hasSubtitles {
                items.append(UIAction(title: "显示字幕", image: UIImage(systemName: "captions.bubble"), state: player.subtitlesEnabled ? .on : .off) { _ in
                    player.subtitlesEnabled.toggle()
                })
            }
            return items
        }
        .frame(width: 44, height: 44)
        .sheet(isPresented: $showsSleepTimer) { SleepTimerSheet() }
    }

    private var sleepTitle: String {
        switch player.sleepMode {
        case .off: "睡眠定时"
        case .endOfTrack: "睡眠定时：本轨结束"
        case .minutes(let minutes): "睡眠定时：\(minutes) 分钟"
        }
    }
}

struct NowPlayingMenuButton: UIViewRepresentable {
    var items: () -> [UIMenuElement]

    final class Coordinator {
        var items: () -> [UIMenuElement]
        init(items: @escaping () -> [UIMenuElement]) { self.items = items }
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 22
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "更多")
        // 每次打开时再取当前的菜单项，而不是在 updateUIView 里换掉菜单打断正在进行的操作。
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
            completion(coordinator?.items() ?? [])
        }])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.items = items
    }
}
