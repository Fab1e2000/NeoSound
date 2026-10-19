import Foundation
import Observation

/// Favorite works, newest first, saved as one JSON file in Application Support (`favorite-works.json`).
@Observable
final class FavoritesStore {
    private(set) var works: [ASMRWork] = []
    private(set) var saveError: String?
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = FavoritesStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            works = (try? JSONDecoder().decode([ASMRWork].self, from: data)) ?? []
        }
    }
    static var defaultFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The earlier test build also kept favorite tracks here; that data is dropped.
        try? FileManager.default.removeItem(at: dir.appending(path: "favorites.json"))
        return dir.appending(path: "favorite-works.json")
    }

    func contains(_ work: ASMRWork) -> Bool { works.contains { $0.id == work.id } }
    func toggle(_ work: ASMRWork) {
        if let index = works.firstIndex(where: { $0.id == work.id }) { works.remove(at: index) }
        else { works.insert(work, at: 0) }
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(works).write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "收藏保存失败：" + error.localizedDescription
        }
    }
}
