import AVFoundation
import Combine
import MediaPlayer
import Observation
import UIKit

enum PlaybackPhase: Equatable {
    case idle, resolving, preparing, playing, paused, buffering, ended
    case failed(String)
}

nonisolated enum SleepTimerMode: Hashable, Sendable {
    case off
    case minutes(Int)
    case endOfTrack
}

nonisolated enum SleepFade {
    static let window: TimeInterval = 30

    /// 定时结束前 `window` 秒线性淡出。
    static func volume(remaining: TimeInterval, fadeEnabled: Bool) -> Float {
        guard fadeEnabled, remaining < window else { return 1 }
        return Float(max(0, remaining / window))
    }
}

/// App 唯一的播放器。每次换曲或停止 generation +1，丢弃过期的异步结果。
@Observable
final class PlaybackCoordinator {
    private(set) var phase: PlaybackPhase = .idle
    private(set) var current: PlayingTrack?
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var activeCue: String?
    private(set) var sleepMode: SleepTimerMode = .off
    private(set) var sleepRemaining: TimeInterval?
    /// 需要告诉用户的一次性播放提示。
    var notice: String?
    var subtitlesEnabled = true {
        didSet { activeCue = subtitlesEnabled ? WebVTT.activeCue(in: cues, at: elapsed)?.text : nil }
    }
    var fadeOut = true
    var isScrubbing = false

    var isPlaying: Bool { phase == .playing || phase == .buffering }
    var hasSubtitles: Bool { !cues.isEmpty }

    private let store: ASMRStore
    private(set) var queue: [PlayingTrack] = []
    var repeatMode = 0 // 0: stop at end, 1: repeat queue, 2: repeat track
    var playbackRate: Float = 1 { didSet { if isPlaying { player.rate = playbackRate }; updateNowPlaying() } }
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    private(set) var subtitleName: String?
    var queueIndex: Int? { current.flatMap { value in queue.firstIndex { $0.id == value.id } } }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var stopAtEnd = false
    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var itemCancellables = Set<AnyCancellable>()
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sleepDeadline: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?

    init(store: ASMRStore) {
        self.store = store
        player.automaticallyWaitsToMinimizeStalling = true
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.syncPhase(with: status) }
            .store(in: &cancellables)
        addTimeObserver()
        observeAudioSession()
        configureRemoteCommands()
    }

    // MARK: 播放控制

    func play(_ track: TrackEntry, in item: ASMRWork, tracks: [TrackEntry]? = nil) {
        if let tracks { queue = tracks.filter { $0.node.type == "audio" && $0.node.stream(preferSmall: store.preferSmall) != nil }.map { PlayingTrack(item:item, track:$0) } }
        let selected = PlayingTrack(item:item, track:track)
        if !queue.contains(where: { $0.id == selected.id }) { queue.append(selected) }
        start(selected)
    }
    private func start(_ selected: PlayingTrack) {
        loadTask?.cancel(); subtitleTask?.cancel(); generation += 1
        let ticket = generation
        player.pause(); player.replaceCurrentItem(with:nil); itemCancellables.removeAll()
        wantsPlayback = true
        current = selected; elapsed = 0; duration = selected.track.duration
        cues = []; activeCue = nil; subtitleName = nil; nowPlayingArtwork = nil
        isScrubbing = false; phase = .resolving
        loadTask = Task { await load(selected, ticket:ticket) }
    }
    func enqueue(_ track: TrackEntry, in item: ASMRWork) {
        guard track.node.type == "audio" else { return }
        let value = PlayingTrack(item:item, track:track)
        if !queue.contains(where: { $0.id == value.id }) { queue.append(value) }
    }
    func removeFromQueue(_ id: String) { if id != current?.id { queue.removeAll { $0.id == id } } }
    func next() {
        guard let index = queueIndex, !queue.isEmpty else { return }
        if index + 1 < queue.count { start(queue[index + 1]) }
        else if repeatMode == 1 { start(queue[0]) }
    }
    func previous() {
        guard let index = queueIndex else { return }
        if elapsed > 3 { seek(to:0) }
        else if index > 0 { start(queue[index - 1]) }
    }
    func selectQueue(_ item: PlayingTrack) { start(item) }
    func shuffleRemaining() {
        guard let current else { return }
        queue = [current] + queue.filter { $0.id != current.id }.shuffled()
    }
    func retry() { if let current { start(current) } }
    func loadSubtitle(_ entry: TrackEntry) {
        guard let url = entry.node.mediaStreamUrl ?? entry.node.mediaDownloadUrl, let current else { return }
        let ticket = generation
        subtitleTask?.cancel()
        subtitleTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from:url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { throw ASMRAPIError.invalidResponse }
                try Task.checkCancellation()
                guard ticket == generation, self.current?.id == current.id else { return }
                let parsed = WebVTT.parseSubtitle(data, filename:entry.title)
                guard !parsed.isEmpty else { throw ASMRAPIError.invalidResponse }
                cues = parsed; subtitleName = entry.title; updateCue()
            } catch { if ticket == generation, !(error is CancellationError) { notice = "字幕载入失败：" + error.localizedDescription } }
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        wantsPlayback = false
        resumeAfterInterruption = false
        player.pause()
        if current != nil { phase = .paused }
        updateNowPlaying()
    }

    func resume() {
        wantsPlayback = true
        guard current != nil else { return }
        if case .failed = phase { retry(); return }
        guard player.currentItem != nil else { return }
        if phase == .ended { seek(to: 0) }
        activateSession()
        player.playImmediately(atRate: playbackRate)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: elapsed + seconds)
    }

    func seek(to seconds: TimeInterval) {
        guard player.currentItem != nil else { return }
        let upper = duration ?? max(seconds, 0)
        let target = min(max(0, seconds), upper)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = target
        if phase == .ended, target < upper { phase = .paused }
        updateCue()
        updateNowPlaying()
    }

    func stop(notice: String? = nil) {
        loadTask?.cancel(); subtitleTask?.cancel(); generation += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemCancellables.removeAll()
        wantsPlayback = false; queue = []; subtitleName = nil
        current = nil
        phase = .idle
        elapsed = 0
        duration = nil
        cues = []
        activeCue = nil
        resumeAfterInterruption = false
        setSleepTimer(.off)
        self.notice = notice
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 睡眠定时

    func setSleepTimer(_ mode: SleepTimerMode) {
        sleepTask?.cancel()
        sleepTask = nil
        player.volume = 1
        sleepMode = mode
        stopAtEnd = mode == .endOfTrack
        switch mode {
        case .off:
            sleepDeadline = nil
            sleepRemaining = nil
            return
        case .minutes(let m):
            sleepDeadline = Date().addingTimeInterval(TimeInterval(m * 60))
        case .endOfTrack:
            sleepDeadline = nil
        }
        updateSleepTimer()
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.updateSleepTimer()
            }
        }
    }

    /// 以真实截止时刻计算剩余，回到前台或系统挂起后再算一次也准确。
    func updateSleepTimer() {
        let remaining: TimeInterval?
        switch sleepMode {
        case .off: return
        case .minutes: remaining = sleepDeadline?.timeIntervalSinceNow
        case .endOfTrack: remaining = duration.map { $0 - elapsed }
        }
        guard let remaining else { sleepRemaining = nil; return }
        sleepRemaining = max(0, remaining)
        if isPlaying {
            player.volume = SleepFade.volume(remaining: remaining, fadeEnabled: fadeOut)
        }
        if remaining <= 0 {
            let wasEnd = sleepMode == .endOfTrack
            pause(); setSleepTimer(.off)
            stopAtEnd = wasEnd
        }
    }

    // MARK: 载入

    private func load(_ selected: PlayingTrack, ticket: Int) async {
        do {
            guard let url = selected.track.node.stream(preferSmall:store.preferSmall) else { throw ASMRAPIError.invalidResponse }
            phase = .preparing
            let asset = AVURLAsset(url:url)
            let playable = try await asset.load(.isPlayable)
            try Task.checkCancellation()
            guard ticket == generation else { return }
            guard playable else { throw ASMRAPIError.invalidResponse }
            let item = AVPlayerItem(asset:asset)
            observe(item); player.replaceCurrentItem(with:item); player.volume = 1
            activateSession()
            if wantsPlayback { player.playImmediately(atRate:playbackRate) } else { phase = .paused }
            updateNowPlaying()
            if let cover = selected.item.coverURL {
                if let (data, _) = try? await URLSession.shared.data(from:cover), let image = UIImage(data:data), ticket == generation {
                    nowPlayingArtwork = MPMediaItemArtwork(boundsSize:image.size) { @Sendable _ in image }
                    updateNowPlaying()
                }
            }
        } catch {
            guard ticket == generation, !(error is CancellationError) else { return }
            phase = .failed("播放失败，点播放重试")
        }
    }

    private func observe(_ item: AVPlayerItem) {
        itemCancellables.removeAll()
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                if status == .failed { self?.phase = .failed("播放失败，请稍后再试") }
            }
            .store(in: &itemCancellables)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.didFinish() }
            .store(in: &itemCancellables)
    }

    private func didFinish() {
        phase = .ended
        if let duration { elapsed = duration }
        if sleepMode == .endOfTrack || stopAtEnd { pause(); setSleepTimer(.off); phase = .ended; updateNowPlaying(); return }
        if repeatMode == 2 { seek(to:0); resume(); return }
        next(); updateNowPlaying()
    }

    private func syncPhase(with status: AVPlayer.TimeControlStatus) {
        guard current != nil else { return }
        switch status {
        case .playing:
            phase = .playing
        case .waitingToPlayAtSpecifiedRate:
            if phase == .playing { phase = .buffering }
        case .paused:
            if phase == .playing || phase == .buffering { phase = .paused }
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    private func addTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.tick(seconds) }
        }
    }

    private func tick(_ seconds: TimeInterval) {
        guard current != nil, !isScrubbing, seconds.isFinite else { return }
        elapsed = seconds
        if let value = player.currentItem?.duration.seconds, value.isFinite, value > 0 { duration = value }
        updateCue()
    }

    private func updateCue() {
        activeCue = subtitlesEnabled ? WebVTT.activeCue(in: cues, at: elapsed)?.text : nil
    }

    // MARK: 音频会话

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 媒体服务重置：丢弃播放器状态，等用户重新点播放。
            MainActor.assumeIsolated { self?.stop(notice: "音频服务已重置，请重新播放") }
        })
    }

    private func handleInterruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            resumeAfterInterruption = wantsPlayback
            wantsPlayback = false
            if current != nil, phase != .ended { phase = .paused }
            updateNowPlaying()
        case .ended:
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options ?? 0).contains(.shouldResume)
            // 打断期间用户手动暂停、定时已结束或已停止，都不自动恢复。
            if shouldResume, resumeAfterInterruption { resume() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    // MARK: 锁屏与远程控制

    private func configureRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        rc.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        rc.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        rc.skipForwardCommand.preferredIntervals = [15]
        rc.skipForwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.skip(by: 15) }
            return .success
        }
        rc.skipBackwardCommand.preferredIntervals = [15]
        rc.skipBackwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        rc.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        rc.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        rc.previousTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.track.title,
            MPMediaItemPropertyAlbumTitle: current.item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
        ]
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = (queueIndex.map { $0 + 1 < queue.count } ?? false) || repeatMode == 1
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = queueIndex != nil
        if let creator = current.item.creator { info[MPMediaItemPropertyArtist] = creator }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
