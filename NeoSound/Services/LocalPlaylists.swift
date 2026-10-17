import Foundation
import Observation
import SwiftUI

/// A playlist kept only on this device. Works are stored as snapshots so the list shows without a network request.
nonisolated struct LocalPlaylist: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var works: [ASMRWork]
}

/// Local playlists saved as one JSON file in Application Support (`playlists.json`).
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
        return dir.appending(path: "playlists.json")
    }

    @discardableResult
    func create(name: String) -> LocalPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = LocalPlaylist(id: UUID(), name: trimmed.isEmpty ? "新列表" : trimmed, createdAt: Date(), works: [])
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
    func contains(_ work: ASMRWork, in id: UUID) -> Bool {
        playlists.first { $0.id == id }?.works.contains { $0.id == work.id } ?? false
    }
    /// Adds the work to the end of the list, or removes it when already there.
    func toggle(_ work: ASMRWork, in id: UUID) {
        guard let index = index(of: id) else { return }
        if let position = playlists[index].works.firstIndex(where: { $0.id == work.id }) {
            playlists[index].works.remove(at: position)
        } else {
            playlists[index].works.append(work)
        }
        save()
    }
    func remove(at offsets: IndexSet, from id: UUID) {
        guard let index = index(of: id) else { return }
        playlists[index].works.remove(atOffsets: offsets)
        save()
    }
    func move(from source: IndexSet, to destination: Int, in id: UUID) {
        guard let index = index(of: id) else { return }
        playlists[index].works.move(fromOffsets: source, toOffset: destination)
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
