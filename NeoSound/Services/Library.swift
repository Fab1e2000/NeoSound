import Foundation
import Observation

/// 目录、白名单与收藏的单一来源。所有入口（首页、搜索、收藏、详情、下一首）都经过这里的准入判断。
@Observable
final class Library {
    private(set) var items: [CatalogItem] = []
    private(set) var allowlist: Allowlist?
    private(set) var loadError: String?
    private(set) var favoriteIds: Set<String>
    /// 白名单每次变化 +1，播放器据此复核当前音轨。
    private(set) var allowlistRevision = 0

    private var originalAllowlist: Allowlist?
    private let defaults: UserDefaults
    private static let favoritesKey = "favoriteItemIds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteIds = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
    }

    var admission: AdmissionService { AdmissionService(allowlist: allowlist) }

    func loadBundledFixtures() {
        do {
            let catalogData = try Data(contentsOf: try Self.resource("catalog", "json"))
            let allowlistData = try Data(contentsOf: try Self.resource("allowlist", "json"))
            items = try JSONDecoder().decode(CatalogSnapshot.self, from: catalogData).items
            let decoded = try Allowlist.decoder.decode(Allowlist.self, from: allowlistData)
            originalAllowlist = decoded
            setAllowlist(decoded)
        } catch {
            // 解码失败不放行：目录清空、白名单为空，全部不可播。
            items = []
            setAllowlist(nil)
            loadError = "目录载入失败"
        }
    }

    // MARK: 准入查询

    func evaluate(_ track: Track, in item: CatalogItem) -> Result<AdmittedTrack, AdmissionDenial> {
        admission.evaluate(track, in: item)
    }

    func isPlayable(_ track: Track, in item: CatalogItem) -> Bool {
        admission.isPlayable(track, in: item)
    }

    func firstPlayable(in item: CatalogItem) -> Track? {
        item.tracks.first { isPlayable($0, in: item) }
    }

    func hasPlayable(_ item: CatalogItem) -> Bool { firstPlayable(in: item) != nil }

    /// 首页只展示至少有一条已准入音轨的作品。
    func recommended(category: Category?) -> [CatalogItem] {
        items.filter { hasPlayable($0) && (category == nil || $0.category == category) }
    }

    /// 搜索可以显示未准入作品（标为不可播放），但不提供播放入口。
    func search(_ query: String) -> [CatalogItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return items.filter {
            $0.title.localizedStandardContains(q)
                || $0.category.label.localizedStandardContains(q)
                || $0.tracks.contains { $0.title.localizedStandardContains(q) }
        }
    }

    func item(withId id: String) -> CatalogItem? { items.first { $0.id == id } }

    // MARK: 收藏

    func isFavorite(_ item: CatalogItem) -> Bool { favoriteIds.contains(item.id) }

    func toggleFavorite(_ item: CatalogItem) {
        if favoriteIds.contains(item.id) { favoriteIds.remove(item.id) } else { favoriteIds.insert(item.id) }
        defaults.set(Array(favoriteIds), forKey: Self.favoritesKey)
    }

    var favorites: [CatalogItem] { items.filter { favoriteIds.contains($0.id) } }

    // MARK: 测试工具：模拟撤销

    func simulateRevocation(of trackId: String) {
        guard var list = allowlist else { return }
        list.revokedTrackIds.insert(trackId)
        setAllowlist(list)
    }

    func restoreAllowlist() { setAllowlist(originalAllowlist) }

    var revokedCount: Int { allowlist?.revokedTrackIds.count ?? 0 }

    private func setAllowlist(_ list: Allowlist?) {
        allowlist = list
        allowlistRevision += 1
    }

    private static func resource(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
