import Foundation
import Synchronization
import Testing
@testable import NeoSound

nonisolated final class APIStubProtocol: URLProtocol, @unchecked Sendable {
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
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(#"{"works":[],"pagination":{"currentPage":1,"pageSize":20,"totalCount":0}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("API 请求边界", .serialized)
@MainActor struct TransportTests {
    private func client() -> ASMRClient {
        APIStubProtocol.requests.withLock { $0 = [] }
        APIStubProtocol.bodies.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIStubProtocol.self]
        return ASMRClient(session:URLSession(configuration:configuration))
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

    @Test func retiredPreferencesAndAccountCacheAreClearedWithoutChangingOthers() {
        let suite = "NeoSoundTests.retiredFilters." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let retired = ["allowedTags", "blockedTags", "excludedTags", "sessionUser", "sessionUserKey"]
        for key in retired { defaults.set(Data("[]".utf8),forKey:key) }
        defaults.set("dark",forKey:"appearance")
        _ = ASMRStore(defaults:defaults,client:ASMRClient())
        for key in retired { #expect(defaults.object(forKey:key) == nil) }
        #expect(defaults.string(forKey:"appearance") == "dark")
    }
    @Test func requestsCarryNoAuthorizationAndUsePublicWorkInfo() async throws {
        let api = client()
        _ = try await api.works(keyword:"$tag:治愈$")
        _ = try? await api.work(1669833)
        let requests = APIStubProtocol.requests.withLock { $0 }
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == nil })
        #expect(requests.last?.url?.path == "/api/workInfo/1669833")
    }
}
