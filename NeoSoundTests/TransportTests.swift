import Foundation
import Synchronization
import Testing
@testable import NeoSound

nonisolated final class APIStubProtocol: URLProtocol, @unchecked Sendable {
    /// A canned (status, JSON) reply; status 0 fails as offline.
    static let reply = Mutex<(Int, String)?>(nil)
    static let requests = Mutex<[URLRequest]>([])
    static let bodies = Mutex<[Data]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating:0,count:1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer,maxLength:buffer.count)
                if count <= 0 { break }
                body.append(contentsOf:buffer.prefix(count))
            }
        }
        Self.bodies.withLock { $0.append(body) }
        if let (status, json) = Self.reply.withLock({ $0 }) {
            if status == 0 { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)); return }
            let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(#"{"works":[],"pagination":{"currentPage":1,"pageSize":20,"totalCount":0}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("API 请求边界", .serialized)
@MainActor struct TransportTests {
    private func client(token: String? = nil) -> ASMRClient {
        APIStubProtocol.reply.withLock { $0 = nil }
        APIStubProtocol.requests.withLock { $0 = [] }
        APIStubProtocol.bodies.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIStubProtocol.self]
        return ASMRClient(token:token,session:URLSession(configuration:configuration))
    }
    private func defaults() -> UserDefaults {
        let suite = "NeoSoundTests.session." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        return defaults
    }
    @Test func loginSendsCredentialsWithoutTokenAndSavesTheNewOne() async throws {
        let api = client(token:"old-placeholder")
        var saved: String?
        let store = ASMRStore(defaults:defaults(),client:api,saveToken:{ saved = $0 })
        APIStubProtocol.reply.withLock { $0 = (200,#"{"user":{"loggedIn":true,"name":"Example"},"token":"new-placeholder"}"#) }
        let credentials = ["name":"测试 User+%","password":" Test+%&/\\\"中文🙂\n "]
        try await store.login(name:credentials["name"]!,password:credentials["password"]!)
        let request = try #require(APIStubProtocol.requests.withLock { $0.first })
        #expect(request.value(forHTTPHeaderField:"Authorization") == nil)
        #expect(try JSONSerialization.jsonObject(with:APIStubProtocol.bodies.withLock { $0[0] }) as? [String:String] == credentials)
        #expect(saved == "new-placeholder" && api.token == "new-placeholder")
        #expect(store.loggedIn && store.user?.name == "Example")
    }
    @Test func accountRequestsCarryTheToken() async throws {
        let api = client(token:"test-placeholder")
        _ = try await api.works()
        #expect(APIStubProtocol.requests.withLock { $0[0] }.value(forHTTPHeaderField:"Authorization") == "Bearer test-placeholder")
    }
    @Test func rejectedLoginKeepsTheExistingSession() async {
        let api = client(token:"test-placeholder")
        let store = ASMRStore(defaults:defaults(),client:api,saveToken:{ _ in })
        APIStubProtocol.reply.withLock { $0 = (401,#"{"error":"用户名或密码错误"}"#) }
        await #expect(throws:ASMRAPIError.self) { try await store.login(name:"test",password:"wrong") }
        #expect(api.token == "test-placeholder" && store.message == nil)
    }
    @Test func sessionSurvivesOfflineAndEndsOnlyWhenRejected() async {
        let api = client(token:"test-placeholder")
        var writes = 0
        let store = ASMRStore(defaults:defaults(),client:api,saveToken:{ _ in writes += 1 })
        for status in [0, 503] {
            APIStubProtocol.reply.withLock { $0 = (status,"{}") }
            await store.refreshSession()
            #expect(store.loggedIn && writes == 0)
        }
        APIStubProtocol.reply.withLock { $0 = (401,#"{"error":"jwt expired"}"#) }
        await store.refreshSession()
        #expect(!store.loggedIn && api.token == nil && writes == 1)
        #expect(store.message == "登录已失效，请重新登录。")
    }
    @Test func accountCacheMatchesTokenAndRenewalIsSaved() async throws {
        let api = client(token:"test-placeholder")
        let settings = defaults()
        var saved: String?
        let store = ASMRStore(defaults:settings,client:api,saveToken:{ saved = $0 })
        APIStubProtocol.reply.withLock { $0 = (200,#"{"user":{"loggedIn":true,"name":"Example"},"token":"renewed-placeholder"}"#) }
        await store.refreshSession()
        #expect(saved == "renewed-placeholder" && store.user?.name == "Example")
        #expect(ASMRStore(defaults:settings,client:ASMRClient(token:saved),saveToken:{ _ in }).user?.name == "Example")
        #expect(ASMRStore(defaults:settings,client:ASMRClient(token:"another"),saveToken:{ _ in }).user == nil)
    }
    @Test func recommendationsPostTheAccountAndAllAgesFilter() async throws {
        let api = client(token:"test-placeholder")
        _ = try await api.recommended(uuid:"uuid-placeholder",page:2)
        _ = try await api.popular()
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests.map(\.url?.path) == ["/api/recommender/recommend-for-user","/api/recommender/popular"])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" })
        let bodies = try APIStubProtocol.bodies.withLock { $0 }.map { try #require(JSONSerialization.jsonObject(with:$0) as? [String:Any]) }
        #expect(bodies[0]["recommenderUuid"] as? String == "uuid-placeholder")
        #expect(bodies[0]["page"] as? Int == 2)
        #expect(bodies.allSatisfy { $0["keyword"] as? String == ContentFilter.excludeAdult })
        #expect(bodies[1]["recommenderUuid"] == nil)
    }
    @Test func switchingHostSignsOut() throws {
        let api = client(token:"test-placeholder")
        var saved: String? = "test-placeholder"
        let store = ASMRStore(defaults:defaults(),client:api,saveToken:{ saved = $0 })
        try store.changeHost(ASMRClient.hosts[1])
        #expect(api.token == nil && saved == nil && api.baseURL.absoluteString == ASMRClient.hosts[1])
    }
    @Test func longSearchUsesPOSTAndRandomOnlyHasSeedWhenSelected() async throws {
        let api = client()
        _ = try await api.works(keyword:String(repeating:"字",count:501))
        _ = try await api.works(sort:.release)
        _ = try await api.works(sort:.random,seed:42)
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests[0].httpMethod == "POST")
        #expect(URLComponents(url:requests[0].url!,resolvingAgainstBaseURL:false)?.percentEncodedPath == "/api/search/")
        let regular = URLComponents(url:requests[1].url!,resolvingAgainstBaseURL:false)!
        let random = URLComponents(url:requests[2].url!,resolvingAgainstBaseURL:false)!
        #expect(regular.queryItems?.contains { $0.name == "seed" } == false)
        #expect(random.queryItems?.first { $0.name == "seed" }?.value == "42")
    }
    @Test func healthySearchAndLongPOSTPreserveKeywords() async throws {
        let api = client()
        _ = try await api.works(keyword:"$tag:健全$",page:2)
        let longKeyword = String(repeating:"字",count:501)
        _ = try await api.works(keyword:longKeyword)
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests[0].url?.path == "/api/search/$tag:健全$")
        #expect(URLComponents(url:requests[0].url!,resolvingAgainstBaseURL:false)?.queryItems?.contains(.init(name:"page",value:"2")) == true)
        #expect(requests[1].httpMethod == "POST")
        let bodies = APIStubProtocol.bodies.withLock { $0 }
        let payload = try #require(JSONSerialization.jsonObject(with:bodies[1]) as? [String:Any])
        #expect(payload["keyword"] as? String == longKeyword)
    }

    @Test func retiredPreferencesAreClearedWithoutChangingOthers() {
        let suite = "NeoSoundTests.retiredFilters." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let retired = ["allowedTags", "blockedTags", "excludedTags", "preferSmall", "asmrBookmarks"]
        for key in retired { defaults.set(Data("[]".utf8),forKey:key) }
        defaults.set("dark",forKey:"appearance")
        _ = ASMRStore(defaults:defaults,client:ASMRClient(),saveToken:{ _ in })
        for key in retired { #expect(defaults.object(forKey:key) == nil) }
        #expect(defaults.string(forKey:"appearance") == "dark")
    }
    @Test func signedOutRequestsCarryNoAuthorizationAndUsePublicWorkInfo() async throws {
        let api = client()
        _ = try await api.works(keyword:"$tag:治愈$")
        _ = try? await api.work(1669833)
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == nil })
        #expect(requests.last?.url?.path == "/api/workInfo/1669833")
    }
}
