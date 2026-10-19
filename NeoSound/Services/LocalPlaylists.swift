import Foundation
import Observation
import SwiftUI

/// One track in a playlist. Stream URLs expire, so only the work snapshot and the track's identity are kept;
/// playback looks the track up again in a fresh file tree.
nonisolated struct PlaylistTrack: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let work: ASMRWork
    let title: String
    let path: String
    let hash: String?
    let duration: Double?

    init(entry: TrackEntry, work: ASMRWork) {
        id = entry.id; self.work = work; title = entry.title; path = entry.path
        hash = entry.node.hash; duration = entry.duration
    }

    /// The same track in a newly loaded tree: by ID, then by file hash, then by folder and file name.
    func resolve(in entries: [TrackEntry]) -> TrackEntry? {
        let audio = entries.filter { $0.node.type == "audio" && $0.node.streamURL != nil }
        return audio.first { $0.id == id }
            ?? hash.flatMap { hash in audio.first { $0.node.hash == hash } }
            ?? audio.first { $0.path == path && $0.title == title }
    }
}

/// A playlist kept only on this device: tracks from any works, played in order.
nonisolated struct LocalPlaylist: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var tracks: [PlaylistTrack]
}

/// Local playlists saved as one JSON file in Application Support (`track-playlists.json`).
@Observable
final class LocalPlaylistStore {
    private(set) var playlists: [LocalPlaylist] = []
    private(set) var saveError: String?
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = LocalPlaylistStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            playlists = (try? decoder.decode([LocalPlaylist].self, from: data)) ?? []
        }
    }
    static var defaultFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Playlists used to hold whole works; that test-only data is dropped rather than migrated.
        try? FileManager.default.removeItem(at: dir.appending(path: "playlists.json"))
        return dir.appending(path: "track-playlists.json")
    }

    @discardableResult
    func create(name: String) -> LocalPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = LocalPlaylist(id: UUID(), name: trimmed.isEmpty ? "新列表" : trimmed, createdAt: Date(), tracks: [])
        playlists.append(playlist)
        save()
        return playlist
    }
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id) else { return }
        playlists[index].name = trimmed
        save()
    }
    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }
    func contains(_ track: TrackEntry, in id: UUID) -> Bool {
        playlists.first { $0.id == id }?.tracks.contains { $0.id == track.id } ?? false
    }
    /// Adds the track to the end of the list, or removes it when already there.
    func toggle(_ track: TrackEntry, of work: ASMRWork, in id: UUID) {
        guard let index = index(of: id) else { return }
        if let position = playlists[index].tracks.firstIndex(where: { $0.id == track.id }) {
            playlists[index].tracks.remove(at: position)
        } else {
            playlists[index].tracks.append(PlaylistTrack(entry: track, work: work))
        }
        save()
    }
    func remove(at offsets: IndexSet, from id: UUID) {
        guard let index = index(of: id) else { return }
        playlists[index].tracks.remove(atOffsets: offsets)
        save()
    }
    func move(from source: IndexSet, to destination: Int, in id: UUID) {
        guard let index = index(of: id) else { return }
        playlists[index].tracks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func index(of id: UUID) -> Int? { playlists.firstIndex { $0.id == id } }
    private func save() {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(playlists).write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "列表保存失败：" + error.localizedDescription
        }
    }
}
