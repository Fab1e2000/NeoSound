import Foundation
import Testing
@testable import NeoSound

@Suite("ASMR 协议与状态", .serialized)
@MainActor struct ASMRTests {
    @Test func searchEscapesSinglePathSegment() throws {
        let keyword = "耳かき / + % ? #"
        let path = "/api/search/" + ASMRClient.encodeSegment(keyword)
        let url = try ASMRClient.makeURL(base:URL(string:"https://api.asmr-200.com")!,path:path,query:[.init(name:"page",value:"2")])
        let components = try #require(URLComponents(url:url,resolvingAgainstBaseURL:false))
        #expect(components.percentEncodedPath.contains("%2F"))
        #expect(components.percentEncodedPath.contains("%25"))
        #expect(components.percentEncodedPath.removingPercentEncoding == "/api/search/" + keyword)
        #expect(components.queryItems == [.init(name:"page",value:"2")])
    }
    @Test func recursiveTracksEmptyURLsAndStableIdentity() throws {
        let json = #"[{"type":"folder","title":"folder","children":[{"type":"audio","title":"a","hash":"h","mediaStreamUrl":"https://example.com/a","streamLowQualityUrl":"","duration":null}]},{"type":"folder","title":"folder","children":[{"type":"audio","title":"a","hash":"h","mediaStreamUrl":"file:///secret"}]}]"#
        let nodes = try JSONDecoder().decode([ASMRNode].self,from:Data(json.utf8))
        let flat = TrackEntry.flatten(nodes,workID:1)
        #expect(flat.count == 2 && flat[0].id != flat[1].id)
        #expect(flat[0].node.stream(preferSmall:true)?.host == "example.com")
        #expect(flat[0].duration == nil)
        #expect(flat[1].node.mediaStreamUrl == nil)
        #expect(flat.map(\.id) == TrackEntry.flatten(nodes,workID:1).map(\.id))
        #expect(flat[0].id != TrackEntry.flatten(nodes,workID:2)[0].id)
    }
    @Test func numericAndStringFacetIDs() throws {
        let data = Data(#"[{"id":1,"name":"tag"},{"id":"uuid","name":"voice"}]"#.utf8)
        let result = try JSONDecoder().decode([ASMRFacet].self,from:data)
        #expect(result.map(\.id) == ["1","uuid"])
    }
    @Test func paginationIgnoresStaleCompletion() async throws {
        let feed = WorkFeed()
        let old = Task { await feed.load(reset:true) { _ in try await Task.sleep(for:.milliseconds(60)); return page(1,ids:[1]) } }
        try await Task.sleep(for:.milliseconds(10))
        await feed.load(reset:true) { _ in page(1,ids:[2]) }
        await old.value
        #expect(feed.works.map(\.id) == [2])
        #expect(!feed.loading)
    }
    @Test func paginationRetainsContentOnFailureAndDeduplicates() async {
        let feed = WorkFeed()
        await feed.load(reset:true) { _ in page(1,ids:[1,2]) }
        await feed.load(reset:false) { _ in page(2,ids:[2,3]) }
        #expect(feed.works.map(\.id) == [1,2,3])
        await feed.load(reset:true) { _ in throw URLError(.timedOut) }
        #expect(feed.works.count == 3 && feed.error != nil && !feed.loading)
    }
    @Test func subtitleFormats() {
        let srt = Data("1\n00:00:01,000 --> 00:00:02,500\nHello\n".utf8)
        #expect(WebVTT.parseSubtitle(srt,filename:"a.srt").first?.start == 1)
        let lrc = Data("[00:01.20]One\n[00:03.00]Two".utf8)
        #expect(WebVTT.parseSubtitle(lrc,filename:"a.lrc").first?.end == 3)
    }
    private func page(_ page: Int, ids: [Int]) -> WorkPage {
        WorkPage(works:ids.map { ASMRWork(id:$0,title:"work \($0)") },pagination:Pagination(currentPage:page,pageSize:2,totalCount:10))
    }


    @Test func automaticPaginationStopsOnFailureAndResumesAfterRetry() async {
        let feed = WorkFeed()
        await feed.load(reset:true) { _ in page(1,ids:[1,2]) }
        var requests = 0
        await feed.load(reset:false,automatically:true) { requested in
            requests += 1
            #expect(requested == 2)
            throw URLError(.timedOut)
        }
        await feed.load(reset:false,automatically:true) { _ in
            requests += 1
            return page(2,ids:[3,4])
        }
        #expect(requests == 1 && feed.page == 1 && feed.works.count == 2)
        await feed.load(reset:false) { requested in
            #expect(requested == 2)
            return WorkPage(works:[ASMRWork(id:3,title:"last")],pagination:Pagination(currentPage:2,pageSize:2,totalCount:3))
        }
        await feed.load(reset:false,automatically:true) { _ in
            Issue.record("Must not request beyond the last page")
            return page(3,ids:[])
        }
        #expect(feed.works.map(\.id) == [1,2,3] && feed.error == nil && !feed.hasNext)
    }

    @Test func automaticPaginationDoesNotDuplicateInflightRequest() async throws {
        let feed = WorkFeed()
        await feed.load(reset:true) { _ in page(1,ids:[1,2]) }
        let pending = Task {
            await feed.load(reset:false,automatically:true) { _ in
                try await Task.sleep(for:.milliseconds(50))
                return page(2,ids:[3,4])
            }
        }
        while !feed.loading { await Task.yield() }
        await feed.load(reset:false,automatically:true) { _ in
            Issue.record("Duplicate page request")
            return page(2,ids:[3,4])
        }
        await pending.value
        #expect(feed.works.map(\.id) == [1,2,3,4])
    }

}
