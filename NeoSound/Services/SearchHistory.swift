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
    /// Appends a backup's entries that are missing here, keeping the newest `limit`.
    func importEntries(_ imported: [SearchEntry]) {
        var seen = Set(entries)
        entries = Array((entries + imported.filter { seen.insert($0).inserted }).prefix(Self.limit))
        save()
    }
    func remove(_ entry: SearchEntry) { entries.removeAll { $0 == entry }; save() }
    func clear() { entries = []; save() }
    private func save() { defaults.set(try? JSONEncoder().encode(entries),forKey:"searchHistory") }
}

/// Tags offered on the search page. The site's tag list mixes in adult tags, so unless R18 is enabled only
/// these all-ages ids are shown; live counts from `/api/tags/` reorder them, and the built-in counts are the fallback.
nonisolated enum HotTags {
    /// The first four hold the all-ages list; the rest only fill with R18 enabled. The last collects
    /// tags the site adds later, until they are given a group here.
    static let groupTitles = ["声音与形式","情感与氛围","角色","题材","外貌与身体","服装与道具","关系与情境","玩法","癖好","作品类型","其他"]
    /// Tag id → index into `groupTitles`: the all-ages list plus every other site tag.
    static let groups: [String: Int] = {
        var groups = Dictionary(uniqueKeysWithValues:raw.map { (String($0.0),$0.3) })
        for (group,ids) in siteGroups { for id in ids { groups[String(id)] = group } }
        return groups
    }()
    /// Site tags outside the all-ages list, by group (from `/api/tags/`, October 2026).
    private static let siteGroups: [Int: [Int]] = [
        0: [60,68,314,432,497,500,502,524,634,639,641,649,651,659],
        1: [4,6,15,25,52,54,57,61,205,247,295,306,494,652],
        2: [39,40,42,43,44,79,80,96,98,147,192,193,197,198,206,207,210,211,212,213,214,215,216,217,218,219,221,223,224,225,226,227,229,230,231,232,233,234,237,239,240,241,242,243,246,248,249,254,269,274,275,276,278,282,283,284,286,287,289,290,291,292,293,303,304,315,317,318,319,399,400,401,405,409,411,412,413,414,415,416,419,422,423,424,425,427,486,505,506,520,521,525,531,534,536,538,541,650,656,660,662],
        3: [2,3,9,11,12,17,20,22,26,30,34,272,298,301,446,447,454,493,519,580,583],
        4: [62,63,65,166,167,170,171,173,174,175,177,178,179,180,181,182,183,184,185,186,187,188,189,191,195,208,255,321,322,472,473,478,537,539,648],
        5: [49,74,75,76,77,81,82,83,85,86,87,88,90,91,92,93,94,99,100,101,102,104,105,107,111,256,257,258,260,262,263,266,312],
        6: [28,31,33,37,46,47,48,118,119,120,123,158,209,222,238,268,270,271,279,281,285,288,302,420,436,437,438,440,462,463,504,529,530,644,645,653,663],
        7: [69,70,112,115,116,122,124,125,126,127,128,131,135,138,145,152,153,160,203,311,433,448,464,487,488,489,499,501,514,523,527,528,532,533,637,646,654,658],
        8: [24,35,50,64,66,67,71,113,114,117,121,129,130,132,133,134,136,137,139,140,141,142,143,144,146,148,149,150,151,154,155,156,157,159,161,162,163,164,165,190,194,199,200,201,202,204,244,245,250,251,265,299,300,307,313,323,324,325,326,426,443,444,445,461,465,484,490,495,522,526,540,642,643,661],
        9: [27,73,296,309,310,434,441,450,451,452,453,491,507,508,509,510,512,515,516,573,588,612,10000,10001]
    ]
    static let allowed: [ASMRFacet] = raw.map { ASMRFacet(id:String($0.0),name:$0.1,count:$0.2) }
    private static let raw: [(Int,String,Int,Int)] = [
        (496,"环绕音",19819,0),(56,"治愈",9520,1),(503,"低语",8712,0),(442,"掏耳",4911,0),(220,"姐姐",4121,2),(51,"萌",4004,1),
        (1,"学校/学园",3647,3),(8,"日常/生活",3309,3),(32,"纯爱",2898,1),(78,"女仆",2608,2),(14,"情侣",2520,2),(16,"幻想",1993,3),
        (13,"温馨",1521,1),(513,"VTuber",1158,2),(58,"皆大欢喜",1141,1),(53,"健全",1101,1),(316,"病娇",993,2),(59,"傲娇",839,2),
        (235,"精灵/妖精",774,2),(176,"兽耳",713,2),(19,"恐怖",616,3),(455,"爱情喜剧",451,3),(55,"感动",331,1),(196,"关西腔",318,0),
        (29,"魔法",283,3),(7,"喜剧",273,3),(638,"吹耳朵",230,0),(636,"陪睡",182,0),(10,"科幻",167,3),(5,"搞笑",164,3),(308,"料理/美食",80,3)
    ]
    /// The allowed tags with the site's current names and counts, most used first; with R18 enabled, every site tag.
    static func ranked(_ site: [ASMRFacet], allowsAdult: Bool = false) -> [ASMRFacet] {
        let byID = Dictionary(site.map { ($0.id,$0) }) { first,_ in first }
        let allowedIDs = Set(allowed.map(\.id))
        let extra = allowsAdult ? site.filter { !allowedIDs.contains($0.id) } : []
        return (allowed.map { byID[$0.id] ?? $0 } + extra).sorted { ($0.count ?? 0) > ($1.count ?? 0) }
    }
    /// Splits tags into the fixed groups, keeping their order within each; empty groups are dropped.
    static func grouped(_ tags: [ASMRFacet]) -> [(title: String, tags: [ASMRFacet])] {
        groupTitles.indices.compactMap { index in
            let members = tags.filter { (groups[$0.id] ?? groupTitles.count - 1) == index }
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
            let visible = try await client.works(keyword:ContentFilter.query(text)).works.filter { ContentFilter.allows($0) }
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
