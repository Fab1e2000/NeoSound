import Foundation
import Testing
@testable import NeoSound

@Suite("ASMR 协议与状态", .serialized)
@MainActor struct ASMRTests {
    @Test func workTitleDropsBracketBlocksAndDetectsJapanese() {
        #expect(WorkTitle.cleaned("【耳かき】癒やしの時間【バイノーラル】") == "癒やしの時間")
        #expect(WorkTitle.cleaned("前 【特典】 後") == "前 後")
        #expect(WorkTitle.cleaned("【只有括号】") == "【只有括号】")
        #expect(WorkTitle.cleaned("[KU100]添い寝(CV:花岩香奈)［中文字幕］耳かき（音声）") == "添い寝 耳かき")
        #expect(WorkTitle.isJapanese("ゆっくりおやすみなさい、お兄ちゃん"))
        #expect(!WorkTitle.isJapanese("在雨声中慢慢入睡吧"))
    }
    @Test func localPlaylistsRenameAndDelete() throws {
        let file = FileManager.default.temporaryDirectory.appending(path:"playlists-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at:file) }
        let store = LocalPlaylistStore(fileURL:file)
        let list = store.create(name:"  睡前  ")
        #expect(store.playlists.map(\.name) == ["睡前"])
        store.rename(list.id,to:"助眠")
        #expect(LocalPlaylistStore(fileURL:file).playlists.map(\.name) == ["助眠"])
        store.delete(list.id)
        #expect(LocalPlaylistStore(fileURL:file).playlists.isEmpty)
    }
    @Test func workContentsGroupsVersionsAndExtras() throws {
        func audio(_ t: String) -> String { #"{"type":"audio","title":"\#(t)","mediaStreamUrl":"https://example.com/\#(t.count)","duration":60}"# }
        let json = """
        [{"type":"folder","title":"02.mp3","children":[{"type":"folder","title":"mp3SEなし","children":[\(audio("01_プロローグ（SEなし）.mp3"))]},\(audio("00_タイトルコール.mp3")),\(audio("01_プロローグ.mp3")),\(audio("ex01寝息ループ.mp3"))]},
         {"type":"folder","title":"01.wav","children":[\(audio("01_プロローグ.wav"))]},
         {"type":"folder","title":"03.特典","children":[{"type":"folder","title":"台本","children":[{"type":"text","title":"01_プロローグ.txt"}]},{"type":"folder","title":"イラスト","children":[{"type":"image","title":"01.png"}]},{"type":"folder","title":"特典ボイス","children":[\(audio("ex02.フリートーク.mp3"))]}]},
         {"type":"text","title":"readme.txt"}]
        """
        let nodes = try JSONDecoder().decode([ASMRNode].self,from:Data(json.utf8))
        let contents = WorkContents(TrackEntry.flatten(nodes,workID:1))
        #expect(contents.formats == ["MP3","WAV"] && contents.hasSEChoice)
        #expect(contents.defaultVersion == TrackVersion(format:"MP3",withSE:true))
        #expect(contents.tracks(for:contents.defaultVersion).map(\.title) == ["00_タイトルコール.mp3","01_プロローグ.mp3","ex01寝息ループ.mp3"])
        #expect(contents.resolve(format:"WAV",withSE:false) == TrackVersion(format:"WAV",withSE:true))
        #expect(contents.scripts.count == 2 && contents.images.count == 1 && contents.bonusAudio.count == 1)
    }
    @Test func trackDisplayNamesDropNumbersAndVersionMarkers() {
        #expect(WorkContents.display("05_お清め耳かき（左）　（SEなし）.mp3") == ("5","お清め耳かき（左）"))
        #expect(WorkContents.display("トラック3_うさギャルちゃんと夜のお散歩_MP3_SEあり.mp3") == ("3","うさギャルちゃんと夜のお散歩"))
        #expect(WorkContents.display("ex01寝息ループ.wav") == ("EX","寝息ループ"))
        #expect(WorkContents.display("Extra Talk.mp3") == (nil,"Extra Talk"))
    }
    @Test func searchQueriesExcludeAdultWorksOnTheServer() throws {
        #expect(ContentFilter.query("",allowsAdult:false) == "$-age:adult$")
        #expect(ContentFilter.query("$tag:治愈$",allowsAdult:false) == "$tag:治愈$ $-age:adult$")
        let path = "/api/search/" + ASMRClient.encodeSegment(ContentFilter.query("$va:浅見ゆい$",allowsAdult:false))
        let url = try ASMRClient.makeURL(base:URL(string:"https://api.asmr-200.com")!,path:path)
        #expect(URLComponents(url:url,resolvingAgainstBaseURL:false)?.percentEncodedPath.removingPercentEncoding == "/api/search/$va:浅見ゆい$ $-age:adult$")
    }
    @Test func enablingR18FiltersNothing() {
        var adult = ASMRWork(id:1,title:"a"); adult.nsfw = true
        #expect(ContentFilter.allows(adult,allowsAdult:true))
        #expect(ContentFilter.query(" $tag:治愈$ ",allowsAdult:true) == "$tag:治愈$")
        #expect(ContentFilter.query("",allowsAdult:true) == "")
    }
    @Test func contentFilterHidesAdultWorksAndPausesOnFilteredPages() async {
        var adult = ASMRWork(id:1,title:"a"); adult.nsfw = true
        var flagged = ASMRWork(id:2,title:"b"); flagged.nsfw = true
        var clean = ASMRWork(id:3,title:"c"); clean.nsfw = false
        #expect(!ContentFilter.allows(adult,allowsAdult:false) && ContentFilter.allows(clean,allowsAdult:false) && ContentFilter.allows(ASMRWork(id:4,title:"d"),allowsAdult:false))
        let feed = WorkFeed()
        let filtered = WorkPage(works:[adult,flagged],pagination:Pagination(currentPage:1,pageSize:2,totalCount:20))
        await feed.load(reset:true) { _ in filtered }
        for _ in 0..<2 { await feed.load(reset:false,automatically:true) { _ in filtered } }
        #expect(feed.works.isEmpty && feed.pausedOnFilteredPages)
        await feed.load(reset:false,automatically:true) { _ in Issue.record("Automatic paging should pause"); return filtered }
        await feed.load(reset:false) { _ in WorkPage(works:[clean],pagination:Pagination(currentPage:2,pageSize:2,totalCount:20)) }
        #expect(feed.works.map(\.id) == [3] && !feed.pausedOnFilteredPages)
    }
    @Test func deepSeekTranslationRequestCarriesNumberedTitles() throws {
        let request = try DeepSeekTitleAPI.request(titles:["耳かき","添い寝"],apiKey:"test-key")
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer test-key")
        let body = try #require(JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
        #expect(body["model"] as? String == "deepseek-flash")
        #expect((body["thinking"] as? [String:Any])?["type"] as? String == "disabled")
        #expect((body["response_format"] as? [String:Any])?["type"] as? String == "json_object")
        let messages = try #require(body["messages"] as? [[String:Any]])
        #expect((messages[0]["content"] as? String)?.contains("JSON") == true)
        #expect((messages[1]["content"] as? String)?.contains(#"{"id":1,"title":"添い寝"}"#) == true)
    }
    @Test func deepSeekTranslationParsesByIDAndIgnoresTruncation() throws {
        let titles = ["耳かき","添い寝"]
        let ok = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"translations\":[{\"id\":1,\"title\":\"陪睡\"},{\"id\":0,\"title\":\" 掏耳 \"},{\"id\":9,\"title\":\"x\"}]}"}}]}"#.utf8)
        #expect(try DeepSeekTitleAPI.parse(ok,titles:titles) == ["耳かき":"掏耳","添い寝":"陪睡"])
        let cut = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"{\"transl"}}]}"#.utf8)
        #expect(try DeepSeekTitleAPI.parse(cut,titles:titles).isEmpty)
    }
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
        #expect(flat[0].node.streamURL?.host == "example.com")
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
