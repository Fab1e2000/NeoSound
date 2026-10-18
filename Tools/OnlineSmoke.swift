import Foundation

/// Read-only live checks using the production URLSession client and models. No media GET.
@main struct OnlineSmoke {
    @MainActor static func main() async throws {
        let api = ASMRClient()
        var results: [String:Any] = [:]
        let first = try await api.works(page:1,sort:.release)
        let second = try await api.works(page:2,sort:.release)
        guard first.pagination.currentPage == 1, second.pagination.currentPage == 2, !first.works.isEmpty else { throw ASMRAPIError.invalidResponse }
        results["list"] = ["page1":first.works.count,"page2":second.works.count,"total":first.pagination.totalCount]
        let found = try await api.works(keyword:"RJ01669833")
        guard found.works.contains(where:{$0.id == 1669833}) else { throw ASMRAPIError.invalidResponse }
        results["search"] = found.works.count
        let work = try await api.work(1669833)
        let entries = TrackEntry.flatten(try await api.tracks(work.id),workID:work.id)
        results["audioCount"] = entries.filter { $0.node.type == "audio" }.count
        for type in ["tags","circles","vas"] {
            let facets: [ASMRFacet] = try await api.request("/api/\(type)/")
            guard !facets.isEmpty else { throw ASMRAPIError.invalidResponse }
            results[type] = facets.count
        }
        let allAges = try await api.works(keyword:ContentFilter.query(""))
        guard !allAges.works.isEmpty, allAges.works.allSatisfy(ContentFilter.allows) else { throw ASMRAPIError.invalidResponse }
        results["allAgesAndR15"] = allAges.pagination.totalCount
        results["time"] = ISO8601DateFormatter().string(from:Date())
        let output = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:output,as:UTF8.self))
    }
}
