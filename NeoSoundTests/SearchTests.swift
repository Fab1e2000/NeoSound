import Foundation
import Testing
@testable import NeoSound

struct SearchTests {
    private func defaults() -> UserDefaults {
        let name = "search-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defaults.removePersistentDomain(forName:name)
        return defaults
    }

    @Test func historyKeepsNewestUniqueEntries() {
        let defaults = defaults()
        let history = SearchHistory(defaults:defaults)
        history.add(.keyword("雨声")); history.add(SearchEntry(kind:.tag,name:"治愈")); history.add(.keyword(" 雨声 "))
        history.add(.keyword("   "))
        #expect(history.entries == [.keyword("雨声"),SearchEntry(kind:.tag,name:"治愈")])
        #expect(SearchHistory(defaults:defaults).entries == history.entries)
        for i in 0..<30 { history.add(.keyword("词 \(i)")) }
        #expect(history.entries.count == SearchHistory.limit)
        #expect(history.entries.first == .keyword("词 29"))
        history.clear()
        #expect(SearchHistory(defaults:defaults).entries.isEmpty)
    }

    @Test func entriesMapToSiteQueries() {
        #expect(SearchEntry.keyword("雨").query == WorkQuery(title:"雨",keyword:"雨"))
        #expect(SearchEntry(kind:.tag,name:"治愈").query.keyword == "$tag:治愈$")
        #expect(SearchEntry(kind:.va,name:"某声优").query.keyword == "$va:某声优$")
    }

    @Test func hotTagsShowOnlyAllowedTagsByLiveCount() {
        let site = [ASMRFacet(id:"56",name:"治愈",count:99999),ASMRFacet(id:"128",name:"成人标签",count:500000)]
        let ranked = HotTags.ranked(site)
        #expect(ranked.first?.name == "治愈")
        #expect(!ranked.contains { $0.id == "128" })
        #expect(ranked.count == HotTags.allowed.count)
        let adult = HotTags.ranked(site,allowsAdult:true)
        #expect(adult.first?.id == "128" && adult.count == HotTags.allowed.count + 1)
        #expect(HotTags.grouped(adult).map(\.title).contains("玩法"))
        #expect(HotTags.grouped([ASMRFacet(id:"99999",name:"新标签")]).map(\.title) == ["其他"])
    }

    @Test func suggestionsKeepDistinctMatchingNames() {
        #expect(SearchSuggester.matching(["雨音","晴空","雨音","小雨","雨林"],"雨") == ["雨音","小雨"])
    }
}

extension SearchTests {
    @Test func everyAllowedTagHasAGroup() {
        #expect(HotTags.allowed.allSatisfy { HotTags.groups[$0.id] != nil })
        let grouped = HotTags.grouped(HotTags.allowed)
        #expect(grouped.map(\.title) == Array(HotTags.groupTitles.prefix(4)))
        #expect(grouped.flatMap(\.tags).count == HotTags.allowed.count)
        #expect(HotTags.grouped(HotTags.allowed.filter { $0.name == "治愈" }).map(\.title) == ["情感与氛围"])
    }

    @Test func countsShortenPastTenThousand() {
        #expect(HotTags.countText(8712) == "8712")
        #expect(HotTags.countText(19819) == "2万")
        #expect(HotTags.countText(12000) == "1.2万")
    }
}
