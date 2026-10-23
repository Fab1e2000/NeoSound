import Foundation

nonisolated struct DownloadFile: Codable, Identifiable, Sendable {
    let id: UUID
    let track: PlaylistTrack
    let type: String
    let expectedBytes: Int64?
    var attemptID: UUID?
    var bytes: Int64 = 0
    var state: State = .queued
    var failure: String?
    enum State: String, Codable, Sendable { case queued, downloading, completed, failed }
    var filename: String {
        let ext = (track.title as NSString).pathExtension.lowercased()
        return id.uuidString + "." + (AudioPlaybackCache.audioExtensions.union(["vtt", "srt", "lrc"]).contains(ext) ? ext : "audio")
    }
}

nonisolated struct VersionDownload: Codable, Identifiable, Sendable {
    let id: UUID
    let work: ASMRWork
    let version: TrackVersion
    let created: Date
    var files: [DownloadFile]
    var paused = false
    var coverFilename: String?
    var audio: [DownloadFile] { files.filter { $0.type == "audio" } }
    var isComplete: Bool { !audio.isEmpty && audio.allSatisfy { $0.state == .completed } }
    var title: String { version.format + (version.withSE ? " · 含音效" : " · 无音效") }
    var finishedCount: Int { audio.filter { $0.state == .completed }.count }
}

/// Transient network samples; cache copies never enter this meter.
nonisolated struct DownloadTransfer {
    var received: Int64 = 0
    var total: Int64?
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    mutating func record(written: Int64, total: Int64, at time: TimeInterval) {
        if written < received { samples = [] }
        received = max(0,written)
        self.total = total > 0 ? total : nil
        samples.append((time,received))
        while samples.count > 2 && samples[1].time < time - 3 { samples.removeFirst() }
    }
    func speed(at time: TimeInterval) -> Double {
        guard let first = samples.first, let last = samples.last,
              time - last.time < 3, time > first.time else { return 0 }
        return max(0,Double(last.bytes - first.bytes) / (time - first.time))
    }
}
nonisolated struct DownloadTransferSummary {
    let received: Int64
    let total: Int64?
    let bytesPerSecond: Double
    var fraction: Double? { total.flatMap { $0 > 0 ? min(1,Double(received) / Double($0)) : nil } }
}
