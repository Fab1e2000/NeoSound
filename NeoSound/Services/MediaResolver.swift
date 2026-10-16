import Foundation

/// 已准入资源的短期播放许可。只能由 `MediaResolver` 实现在本文件内构造。
nonisolated struct VerifiedPlaybackGrant: Sendable {
    let url: URL
    let trackId: String
    let revision: String
    let allowlistVersion: Int
    let expiresAt: Date

    fileprivate init(url: URL, admitted: AdmittedTrack, expiresAt: Date) {
        self.url = url
        self.trackId = admitted.track.id
        self.revision = admitted.track.revision
        self.allowlistVersion = admitted.allowlistVersion
        self.expiresAt = expiresAt
    }
}

nonisolated enum MediaResolverError: Error {
    case resourceMissing
}

protocol MediaResolver: Sendable {
    func grant(for admitted: AdmittedTrack) async throws -> VerifiedPlaybackGrant
}

/// Mock：把已准入的音轨映射到 App 内置的自有测试音频。真实接入时换成向服务端申请短期 URL。
nonisolated struct BundledMediaResolver: MediaResolver {
    private static let resources: [String: String] = [
        "syn-track-rain-30": "rain",
        "syn-track-rain-long": "rain",
        "syn-track-waves": "waves",
        "syn-track-forest": "forest",
        "syn-track-fire": "fire",
        "syn-track-pink": "pink",
    ]

    func grant(for admitted: AdmittedTrack) async throws -> VerifiedPlaybackGrant {
        guard let name = Self.resources[admitted.track.id],
              let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            throw MediaResolverError.resourceMissing
        }
        return VerifiedPlaybackGrant(url: url, admitted: admitted, expiresAt: Date().addingTimeInterval(600))
    }

    /// 字幕同样只在音轨已准入时提供。
    func subtitleURL(for ref: SubtitleRef, admitted: AdmittedTrack) -> URL? {
        guard ref.format == .webvtt else { return nil }
        return Bundle.main.url(forResource: ref.id, withExtension: "vtt")
    }
}
