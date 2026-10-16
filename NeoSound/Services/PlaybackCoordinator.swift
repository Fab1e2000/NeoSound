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
    private(set) var current: AdmittedTrack?
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var activeCue: String?
    private(set) var sleepMode: SleepTimerMode = .off
    private(set) var sleepRemaining: TimeInterval?
    /// 需要告诉用户的一次性提示（例如音轨被撤销）。
    var notice: String?
    var subtitlesEnabled = true {
        didSet { activeCue = subtitlesEnabled ? WebVTT.activeCue(in: cues, at: elapsed)?.text : nil }
    }
    var fadeOut = true
    var isScrubbing = false

    var isPlaying: Bool { phase == .playing || phase == .buffering }
    var hasSubtitles: Bool { !cues.isEmpty }

    private let library: Library
    private let resolver: BundledMediaResolver
    @ObservationIgnored var artworkProvider: ((ArtworkStyle) -> UIImage?)?
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var itemCancellables = Set<AnyCancellable>()
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sleepDeadline: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?

    init(library: Library, resolver: BundledMediaResolver = BundledMediaResolver()) {
        self.library = library
        self.resolver = resolver
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

    func play(_ track: Track, in item: CatalogItem) {
        generation += 1
        let ticket = generation
        switch library.evaluate(track, in: item) {
        case .failure(let denial):
            phase = .failed(denial.userMessage)
        case .success(let admitted):
            if current?.track.id == track.id, phase != .idle {
                resume()
                return
            }
            phase = .resolving
            Task { await load(admitted, ticket: ticket) }
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        resumeAfterInterruption = false
        player.pause()
        if current != nil { phase = .paused }
        updateNowPlaying()
    }

    func resume() {
        guard let current else { return }
        // 恢复播放同样要过准入。
        guard case .success = library.evaluate(current.track, in: current.item) else {
            stop(notice: "这条音轨已下架，播放已停止")
            return
        }
        if phase == .ended { seek(to: 0) }
        activateSession()
        player.play()
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
        generation += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemCancellables.removeAll()
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

    /// 白名单变化后复核当前音轨；不再准入则立即停止并清理。
    func revalidate() {
        guard let current else { return }
        if case .failure = library.evaluate(current.track, in: current.item) {
            stop(notice: "「\(current.track.title)」已下架，播放已停止")
        }
    }

    // MARK: 睡眠定时

    func setSleepTimer(_ mode: SleepTimerMode) {
        sleepTask?.cancel()
        sleepTask = nil
        player.volume = 1
        sleepMode = mode
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
            pause()
            setSleepTimer(.off)
        }
    }

    // MARK: 载入

    private func load(_ admitted: AdmittedTrack, ticket: Int) async {
        do {
            let grant = try await resolver.grant(for: admitted)
            guard ticket == generation else { return }
            phase = .preparing
            let asset = AVURLAsset(url: grant.url)
            let (playable, assetDuration) = try await asset.load(.isPlayable, .duration)
            guard ticket == generation else { return }
            guard playable else {
                phase = .failed("暂不支持此资源")
                return
            }
            // 异步期间白名单可能变了，挂上播放器前再复核一次。
            guard case .success(let fresh) = library.evaluate(admitted.track, in: admitted.item) else {
                phase = .failed("此音轨暂时不能播放")
                return
            }
            current = fresh
            let seconds = assetDuration.seconds
            duration = assetDuration.isNumeric && seconds > 0 ? seconds : admitted.track.duration
            elapsed = 0
            cues = loadCues(for: fresh)
            activeCue = nil
            nowPlayingArtwork = makeArtwork(for: fresh.item.artwork)

            let item = AVPlayerItem(asset: asset)
            observe(item)
            player.replaceCurrentItem(with: item)
            player.volume = 1
            activateSession()
            player.play()
            updateNowPlaying()
        } catch {
            guard ticket == generation else { return }
            phase = .failed("播放失败，请稍后再试")
        }
    }

    private func loadCues(for admitted: AdmittedTrack) -> [SubtitleCue] {
        guard let ref = admitted.track.subtitles.first,
              let url = resolver.subtitleURL(for: ref, admitted: admitted),
              let data = try? Data(contentsOf: url) else { return [] }
        return WebVTT.parse(data)
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
        if sleepMode == .endOfTrack { setSleepTimer(.off) }
        updateNowPlaying()
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
            resumeAfterInterruption = isPlaying
            if current != nil, phase != .ended { phase = .paused }
            updateNowPlaying()
        case .ended:
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options ?? 0).contains(.shouldResume)
            // 打断期间用户手动暂停、定时已结束或被撤销，都不自动恢复。
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
        rc.nextTrackCommand.isEnabled = false
        rc.previousTrackCommand.isEnabled = false
    }

    private func makeArtwork(for style: ArtworkStyle) -> MPMediaItemArtwork? {
        guard let image = artworkProvider?(style) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let creator = current.item.creator { info[MPMediaItemPropertyArtist] = creator }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
