import Foundation
import Observation

/// One search the user ran: free text, or a tag, circle or voice actor picked from suggestions.
struct SearchEntry: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case keyword, tag, circle, va }
    var kind: Kind
    var name: String
    static func keyword(_ name: String) -> SearchEntry { SearchEntry(kind:.keyword,name:name) }
    var query: WorkQuery {
        switch kind {
        case .keyword: WorkQuery(title:name,keyword:name)
        case .tag: .tag(name)
        case .circle: .circle(name)
        case .va: .va(name)
        }
    }
    var kindLabel: String? {
        switch kind {
        case .keyword: nil
        case .tag: "标签"
        case .circle: "社团"
        case .va: "声优"
        }
    }
}

/// Recent searches, newest first, kept in UserDefaults (`searchHistory`).
@Observable
final class SearchHistory {
    static let limit = 20
    private(set) var entries: [SearchEntry] = []
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey:"searchHistory") {
            entries = (try? JSONDecoder().decode([SearchEntry].self,from:data)) ?? []
        }
    }
    func add(_ entry: SearchEntry) {
        let name = entry.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let entry = SearchEntry(kind:entry.kind,name:name)
        entries.removeAll { $0 == entry }
        entries.insert(entry,at:0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }
    func remove(_ entry: SearchEntry) { entries.removeAll { $0 == entry }; save() }
    func clear() { entries = []; save() }
    private func save() { defaults.set(try? JSONEncoder().encode(entries),forKey:"searchHistory") }
}

/// All-ages tags offered on the search page. The site's tag list mixes in adult tags, so only these ids
/// are ever shown; live counts from `/api/tags/` reorder them, and the built-in counts are the fallback.
nonisolated enum HotTags {
    static let groupTitles = ["声音与形式","情感与氛围","角色","题材"]
    /// Tag id → index into `groupTitles`.
    static let groups: [String: Int] = Dictionary(uniqueKeysWithValues:raw.map { (String($0.0),$0.3) })
    static let allowed: [ASMRFacet] = raw.map { ASMRFacet(id:String($0.0),name:$0.1,count:$0.2) }
    private static let raw: [(Int,String,Int,Int)] = [
        (496,"环绕音",19819,0),(56,"治愈",9520,1),(503,"低语",8712,0),(442,"掏耳",4911,0),(220,"姐姐",4121,2),(51,"萌",4004,1),
        (1,"学校/学园",3647,3),(8,"日常/生活",3309,3),(32,"纯爱",2898,1),(78,"女仆",2608,2),(14,"情侣",2520,2),(16,"幻想",1993,3),
        (13,"温馨",1521,1),(513,"VTuber",1158,2),(58,"皆大欢喜",1141,1),(53,"健全",1101,1),(316,"病娇",993,2),(59,"傲娇",839,2),
        (235,"精灵/妖精",774,2),(176,"兽耳",713,2),(19,"恐怖",616,3),(455,"爱情喜剧",451,3),(55,"感动",331,1),(196,"关西腔",318,0),
        (29,"魔法",283,3),(7,"喜剧",273,3),(638,"吹耳朵",230,0),(636,"陪睡",182,0),(10,"科幻",167,3),(5,"搞笑",164,3),(308,"料理/美食",80,3)
    ]
    /// The allowed tags with the site's current names and counts, most used first.
    static func ranked(_ site: [ASMRFacet]) -> [ASMRFacet] {
        let byID = Dictionary(site.map { ($0.id,$0) }) { first,_ in first }
        return allowed.map { byID[$0.id] ?? $0 }.sorted { ($0.count ?? 0) > ($1.count ?? 0) }
    }
    /// Splits tags into the fixed groups, keeping their order within each; empty groups are dropped.
    static func grouped(_ tags: [ASMRFacet]) -> [(title: String, tags: [ASMRFacet])] {
        groupTitles.indices.compactMap { index in
            let members = tags.filter { groups[$0.id] == index }
            return members.isEmpty ? nil : (groupTitles[index],members)
        }
    }
    /// Work counts as shown on chips: 8712, 1.9万.
    static func countText(_ count: Int) -> String {
        count < 10000 ? String(count) : (Double(count) / 10000).formatted(.number.precision(.fractionLength(0...1))) + "万"
    }
}

/// Live suggestions for the text being typed: the first matching works, and circles and voice actors
/// named in them. Results come through the same all-ages search as the work lists.
@Observable
final class SearchSuggester {
    private(set) var works: [ASMRWork] = []
    private(set) var circles: [String] = []
    private(set) var vas: [String] = []
    private(set) var loading = false
    func update(_ text: String, client: ASMRClient) async {
        loading = true
        do {
            // Debounce: a new keystroke cancels this task before the request goes out.
            try await Task.sleep(for:.milliseconds(300))
            let visible = try await client.works(keyword:ContentFilter.query(text)).works.filter(ContentFilter.allows)
            try Task.checkCancellation()
            works = Array(visible.prefix(3))
            circles = Self.matching(visible.compactMap(\.circle?.name),text)
            vas = Self.matching(visible.flatMap { $0.vas ?? [] }.map(\.name),text)
        } catch {
            if Task.isCancelled { return }
            works = []; circles = []; vas = []
        }
        loading = false
    }
    nonisolated static func matching(_ names: [String], _ text: String, limit: Int = 2) -> [String] {
        var seen = Set<String>()
        return Array(names.filter { $0.localizedStandardContains(text) && seen.insert($0).inserted }.prefix(limit))
    }
}
