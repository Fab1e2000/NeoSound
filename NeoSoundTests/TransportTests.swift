import Foundation
import Synchronization
import Testing
@testable import NeoSound

nonisolated final class APIStubProtocol: URLProtocol, @unchecked Sendable {
    static let sessionReply = Mutex<(Int, String)?>(nil)
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
        if let (status, json) = Self.sessionReply.withLock({ $0 }) {
            if status == 0 { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)); return }
            let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let unauthorized = request.url!.path == "/api/unauthorized"
        let response = HTTPURLResponse(url:request.url!,statusCode:unauthorized ? 401:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data((unauthorized ? #"{"error":"jwt expired"}"# : #"{"user":{"loggedIn":false},"works":[],"pagination":{"currentPage":1,"pageSize":20,"totalCount":0}}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("API 请求边界", .serialized)
@MainActor struct TransportTests {
    private func client() -> ASMRClient {
        APIStubProtocol.sessionReply.withLock { $0 = nil }
        APIStubProtocol.requests.withLock { $0 = [] }
        APIStubProtocol.bodies.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIStubProtocol.self]
        return ASMRClient(token:"test-only-placeholder",session:URLSession(configuration:configuration))
    }
    @Test func bearerExcludedFromLoginAndIncludedForAccountRequests() async throws {
        let api = client()
        let _: AuthResponse = try await api.request("/api/auth/me",method:"POST",body:["name":"example","password":"test-only"],sendToken:false)
        let _: AuthResponse = try await api.request("/api/auth/me")
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests[0].value(forHTTPHeaderField:"Authorization") == nil)
        #expect(requests[0].value(forHTTPHeaderField:"Content-Type") == "application/json")
        #expect(requests[1].value(forHTTPHeaderField:"Authorization") == "Bearer test-only-placeholder")
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
    @Test func unauthorizedTriggersSessionInvalidation() async {
        let api = client()
        var invalidated = false
        api.onAuthenticationFailure = { invalidated = true; api.token = nil }
        do { _ = try await api.data("/api/unauthorized"); Issue.record("Expected HTTP failure") } catch {}
        #expect(invalidated && api.token == nil)
    }
    @Test func requiredAuthenticationFailsBeforeTransport() async {
        let api = client(); api.token = nil
        do { _ = try await api.data("/api/playlist/create-playlist",method:"POST",authenticated:true); Issue.record("Expected missing login") } catch {}
        #expect(APIStubProtocol.requests.withLock { $0.isEmpty })
    }
    @Test func credentialsArriveUnmodifiedAsJSON() async throws {
        let api = client()
        let credentials = ["name":"测试 User+%", "password":" Test+%&/\\\"中文🙂\n "]
        let _: AuthResponse = try await api.request("/api/auth/me",method:"POST",body:credentials,sendToken:false)
        let body = APIStubProtocol.bodies.withLock { $0[0] }
        #expect(try JSONSerialization.jsonObject(with:body) as? [String:String] == credentials)
    }
    @Test func rejectedLoginDoesNotInvalidateExistingSession() async {
        let api = client()
        var invalidated = false
        api.onAuthenticationFailure = { invalidated = true }
        do {
            _ = try await api.data("/api/unauthorized",method:"POST",body:["name":"test","password":"test"],sendToken:false)
            Issue.record("Expected HTTP failure")
        } catch { #expect(error.localizedDescription.contains("401")) }
        #expect(!invalidated)
        #expect(api.token == "test-only-placeholder")
    }
    @Test func restoredSessionSurvivesOfflineAndServerFailures() async {
        let api = client()
        let suite = "NeoSoundTests.session." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); APIStubProtocol.sessionReply.withLock { $0 = nil } }
        var vaultWrites = 0
        let store = ASMRStore(defaults:defaults,client:api,saveToken:{ _ in vaultWrites += 1 })
        #expect(store.loggedIn)
        for status in [0, 503] {
            APIStubProtocol.sessionReply.withLock { $0 = (status, "{}") }
            await store.refreshSession()
            #expect(store.loggedIn && api.token == "test-only-placeholder")
            #expect(store.sessionRevision == 0 && vaultWrites == 0)
        }
        APIStubProtocol.sessionReply.withLock { $0 = (401, #"{"error":"jwt expired"}"#) }
        await store.refreshSession()
        #expect(!store.loggedIn && api.token == nil)
        #expect(store.sessionRevision == 1 && vaultWrites == 1)
    }

    @Test func accountRestoresWithMatchingTokenAndAcceptsRenewal() async {
        let api = client()
        let suite = "NeoSoundTests.restore." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); APIStubProtocol.sessionReply.withLock { $0 = nil } }
        var savedToken: String?
        let store = ASMRStore(defaults:defaults,client:api,saveToken:{ savedToken = $0 })
        APIStubProtocol.sessionReply.withLock { $0 = (200, #"{"user":{"loggedIn":true,"name":"Example"},"token":"renewed-test-token"}"#) }
        await store.refreshSession()
        #expect(savedToken == "renewed-test-token")
        #expect(store.user?.name == "Example" && store.sessionRevision == 0)
        let restored = ASMRStore(defaults:defaults,client:ASMRClient(token:savedToken),saveToken:{ _ in })
        #expect(restored.loggedIn && restored.user?.name == "Example")
        let different = ASMRStore(defaults:defaults,client:ASMRClient(token:"another-token"),saveToken:{ _ in })
        #expect(different.user == nil)
        store.report(ASMRAPIError.response(401,"old request"))
        #expect(store.loggedIn)
        try? restored.logout()
        #expect(defaults.data(forKey:"sessionUser") == nil)
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

    @Test func retiredTagFiltersAreClearedWithoutChangingOtherPreferences() {
        let suite = "NeoSoundTests.retiredFilters." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        for key in ["allowedTags", "blockedTags", "excludedTags"] { defaults.set(Data("[]".utf8),forKey:key) }
        defaults.set("dark",forKey:"appearance")
        _ = ASMRStore(defaults:defaults,client:ASMRClient(),saveToken:{ _ in })
        for key in ["allowedTags", "blockedTags", "excludedTags"] { #expect(defaults.object(forKey:key) == nil) }
        #expect(defaults.string(forKey:"appearance") == "dark")
    }
}
