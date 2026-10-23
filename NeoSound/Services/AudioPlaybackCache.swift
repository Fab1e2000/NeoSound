import AVFoundation
import Foundation
import Observation

/// Listened audio kept in Caches/ListeningAudio, ported from NeoDizzy. Only complete, validated files enter
/// the index; the least recently played go first once the chosen capacity is exceeded.
@Observable final class AudioPlaybackCache {
    static let shared = AudioPlaybackCache()
    static let capacityKey = "audioCache.capacityGB"
    /// Capacity choices in GB; 0 turns caching off.
    static let capacityChoices = [0, 1, 2, 5, 10]
    nonisolated static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

    nonisolated struct Entry: Codable, Sendable {
        let key: String
        let filename: String
        let bytes: Int64
        var used: Date
        var original: Bool?
    }
    /// A track's identity across fresh file trees: its file hash, else the work, folder and file name.
    /// The same rule playlists use to find a track again.
    nonisolated static func key(for track: TrackEntry, workID: Int) -> String {
        track.node.hash ?? "\(workID)|\(track.path)|\(track.title)"
    }
    nonisolated static func mayContinue(listened: TimeInterval, duration: TimeInterval) -> Bool {
        listened.isFinite && duration.isFinite && duration > 0 && listened / duration > 0.9
    }

    private(set) var bytes: Int64 = 0
    private(set) var issue: String?
    let directory: URL
    var capacityGB: Int {
        didSet { defaults.set(capacityGB, forKey: Self.capacityKey); if capacityGB == 0 { clear() } else { trim(); save() } }
    }
    var capacity: Int64 { capacityOverride ?? Int64(capacityGB) * 1_024 * 1_024 * 1_024 }
    /// A byte capacity for tests, instead of whole gigabytes.
    @ObservationIgnored private let capacityOverride: Int64?
    var isEnabled: Bool { capacityGB > 0 }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored private var jobs: [UUID: ProgressiveAudioLoader] = [:]
    @ObservationIgnored private var discarded = Set<UUID>()
    @ObservationIgnored private var completed = Set<UUID>()
    @ObservationIgnored private var detached: [UUID] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeFiles = Set<URL>()
    @ObservationIgnored private var exportingFiles: [URL: Int] = [:]

    init(directory: URL = URL.cachesDirectory.appendingPathComponent("ListeningAudio", isDirectory: true), defaults: UserDefaults = .standard,
         capacityOverride: Int64? = nil) {
        self.directory = directory; self.defaults = defaults; self.capacityOverride = capacityOverride
        capacityGB = defaults.object(forKey: Self.capacityKey) as? Int ?? 2
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved.filter { _, entry in
                guard entry.filename == URL(fileURLWithPath: entry.filename).lastPathComponent else { return false }
                let size = try? directory.appendingPathComponent(entry.filename).resourceValues(forKeys: [.fileSizeKey]).fileSize
                return size.map(Int64.init) == entry.bytes && entry.bytes > 0
            }
        }
        // Leftover partial spools and files the index does not know about.
        let known = Set(entries.values.map(\.filename)).union(["index.json"])
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !known.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        trim(); save()
    }

    /// The cached file for a track, marked as just used; nil when missing or damaged.
    func file(for key: String) -> URL? {
        guard var entry = entries[key] else { return nil }
        let url = directory.appendingPathComponent(entry.filename)
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == entry.bytes else {
            entries[key] = nil; save(); return nil
        }
        entry.used = .now; entries[key] = entry; save()
        return url
    }
    /// Only newly verified original streams are eligible; old/low-quality cache entries remain playable.
    func exportOriginal(for track: PlaylistTrack, expectedBytes: Int64?, to destination: URL) async throws -> URL? {
        let key = track.hash ?? "\(track.work.id)|\(track.path)|\(track.title)"
        guard let entry = entries[key], entry.original == true,
              expectedBytes == nil || expectedBytes == entry.bytes,
              let source = file(for:key), Self.audioExtensions.contains(source.pathExtension) else { return nil }
        exportingFiles[source,default:0] += 1
        defer {
            exportingFiles[source,default:1] -= 1
            if exportingFiles[source] == 0 { exportingFiles[source] = nil }
            if !activeFiles.contains(source), exportingFiles[source] == nil, !entries.values.contains(where: { $0.filename == source.lastPathComponent }) {
                try? FileManager.default.removeItem(at:source)
            }
        }
        try await Task.detached(priority:.utility) {
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.copyItem(at:source,to:destination)
        }.value
        return destination
    }
    /// The file being played is never evicted; the previous one is released.
    func protect(_ url: URL?) {
        protectFiles(Set([url].compactMap { $0 }))
    }
    func protectFiles(_ urls: Set<URL>) {
        let previous = activeFiles
        activeFiles = urls
        for old in previous.subtracting(activeFiles) where exportingFiles[old] == nil && old.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path && !entries.values.contains(where: { $0.filename == old.lastPathComponent }) {
            try? FileManager.default.removeItem(at: old)
        }
    }
    func remove(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        let url = directory.appendingPathComponent(entry.filename)
        if !activeFiles.union(exportingFiles.keys).contains(url) { try? FileManager.default.removeItem(at: url) }
        save()
    }

    /// A player item that streams `url` while spooling it to disk; nil when caching is off or the file
    /// is larger than the whole cache (the caller then plays the URL directly).
    func makeItem(url: URL, key: String, expectedBytes: Int64?, original: Bool = false, configuration: URLSessionConfiguration = .ephemeral) -> (AVPlayerItem, UUID)? {
        guard isEnabled, (expectedBytes ?? 0) <= capacity else { return nil }
        let id = UUID(), generation = generation
        do {
            let loader = try ProgressiveAudioLoader(url: url, directory: directory, maxBytes: max(capacity, expectedBytes ?? 0), configuration: configuration) { [weak self] file, size, ext in
                Task { @MainActor [weak self] in
                    defer { if let file { try? FileManager.default.removeItem(at: file) } }
                    guard let self else { return }
                    if self.discarded.remove(id) == nil, self.generation == generation, let file {
                        do { try self.commit(file, key: key, bytes: size, fileExtension: ext, original: original) }
                        catch { self.issue = "音频缓存保存失败，请检查可用空间。" }
                    }
                    guard self.jobs[id] != nil else { return }
                    self.completed.insert(id)
                    if self.detached.contains(id) { self.jobs[id] = nil; self.completed.remove(id) }
                    self.detached.removeAll { $0 == id }
                    // Active loaders remain alive to serve AVFoundation after the transfer finishes.
                }
            }
            jobs[id] = loader
            return (loader.makeItem(), id)
        } catch { issue = "无法创建音频缓存，已改为在线播放。"; return nil }
    }
    /// Drops a job whose file must not be kept, such as one that failed to play.
    func discard(_ id: UUID?) {
        guard let id else { return }
        if completed.remove(id) == nil { discarded.insert(id) }
        detached.removeAll { $0 == id }
        jobs.removeValue(forKey: id)?.cancel()
    }
    /// Called when playback moves away from a track: a nearly finished one keeps downloading in the background.
    func leave(_ id: UUID?, listened: TimeInterval, duration: TimeInterval) {
        guard let id, let job = jobs[id] else { return }
        if completed.remove(id) != nil { jobs[id] = nil; return }
        if Self.mayContinue(listened: listened, duration: duration) {
            detached.append(id)
            // Bound background work; the active track is never evicted here.
            while detached.count > 2 { let oldest = detached.removeFirst(); jobs.removeValue(forKey: oldest)?.cancel() }
        } else { jobs[id] = nil; job.cancel() }
    }
    func commit(_ file: URL, key: String, bytes: Int64, fileExtension: String, original: Bool = false) throws {
        guard bytes > 0, bytes <= capacity,
              (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == bytes else { throw ASMRAPIError.invalidResponse }
        let ext = Self.audioExtensions.contains(fileExtension.lowercased()) ? fileExtension.lowercased() : "audio"
        let filename = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent(filename))
        if let old = entries[key], !activeFiles.union(exportingFiles.keys).contains(directory.appendingPathComponent(old.filename)) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.filename))
        }
        entries[key] = Entry(key: key, filename: filename, bytes: bytes, used: .now, original: original)
        trim(); save()
    }
    /// In-flight streams keep serving playback, but cannot repopulate a cleared cache.
    func clear() {
        generation += 1; issue = nil
        for id in detached { jobs.removeValue(forKey: id)?.cancel() }
        detached.removeAll()
        for (key, entry) in entries {
            let url = directory.appendingPathComponent(entry.filename)
            if activeFiles.union(exportingFiles.keys).contains(url) { entries[key] = nil; continue }
            do { try FileManager.default.removeItem(at: url); entries[key] = nil }
            catch { issue = "部分缓存未能删除，请稍后重试。" }
        }
        save()
    }
    private func trim() {
        var total = entries.values.reduce(Int64(0)) { $0 + $1.bytes }
        for entry in entries.values.sorted(by: { $0.used < $1.used }) where total > capacity {
            let url = directory.appendingPathComponent(entry.filename)
            guard !activeFiles.union(exportingFiles.keys).contains(url) else { continue }
            do { try FileManager.default.removeItem(at: url); entries[entry.key] = nil; total -= entry.bytes } catch {}
        }
    }
    private func save() {
        bytes = entries.values.reduce(0) { $0 + $1.bytes }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic) }
    }
}
