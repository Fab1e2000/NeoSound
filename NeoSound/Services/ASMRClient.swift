import Foundation
import Security
import Observation

nonisolated enum ASMRAPIError: LocalizedError {
    case response(Int, String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .response(let status, let message): "\(message)（\(status)）"
        case .invalidResponse: "服务器返回了无法识别的数据"
        }
    }
}
nonisolated enum TokenVault {
    static let service = "com.elsterlee.NeoSound.asmr"
    static func read(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                               kSecAttrAccount as String: account, kSecReturnData as String: true]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String?, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let token {
            let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            if status == errSecItemNotFound { status = SecItemAdd(q.merging(attrs) { _, b in b } as CFDictionary, nil) }
            guard status == errSecSuccess else { throw ASMRAPIError.response(Int(status), "无法安全保存登录信息") }
        } else {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ASMRAPIError.response(Int(status), "无法清除登录信息") }
        }
    }
}

/// Client for the site's API. Only this first-party client receives the login token;
/// covers and media are fetched separately from the URLs it returns and never inherit it.
@Observable final class ASMRClient {
    static let hosts = ["https://api.asmr-200.com", "https://api.asmr.one", "https://api.asmr-100.com", "https://api.asmr-300.com"]
    var baseURL: URL
    var token: String?
    @ObservationIgnored var onAuthenticationFailure: (() -> Void)?
    private let session: URLSession
    init(baseURL: URL = URL(string: hosts[0])!, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL; self.token = token; self.session = session
    }
    static func makeURL(base: URL, path: String, query: [URLQueryItem] = []) throws -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        // path is decoded here, so '%' and '/' inside keyword must be encoded as one segment by caller.
        c.percentEncodedPath = path
        c.queryItems = query.isEmpty ? nil : query
        guard let url = c.url else { throw ASMRAPIError.invalidResponse }
        return url
    }
    static func encodeSegment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }
    func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil, sendToken: Bool = true) async throws -> T {
        let data = try await data(path, query: query, method: method, body: body, sendToken: sendToken)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func data(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil, sendToken: Bool = true) async throws -> Data {
        let requestToken = sendToken ? token : nil
        let requestOrigin = baseURL
        var r = URLRequest(url: try Self.makeURL(base: baseURL, path: path, query: query))
        r.httpMethod = method; r.timeoutInterval = 25
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        if let requestToken { r.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: r, delegate: APIOriginGuard(origin:baseURL))
        guard let http = response as? HTTPURLResponse else { throw ASMRAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["error"] as? String ?? "请求失败，请稍后重试"
            // Only a rejection of the token still in use ends the session; a wrong password at login does not.
            if requestToken != nil, requestToken == token, requestOrigin == baseURL,
               http.statusCode == 401 || message == "jwt expired" || message == "No authorization token was found" {
                onAuthenticationFailure?()
            }
            throw ASMRAPIError.response(http.statusCode, message)
        }
        return data
    }
    func works(keyword: String = "", page: Int = 1, sort: WorkSort = .create_date, ascending: Bool = false, subtitle: Bool = false, seed: Int = 0) async throws -> WorkPage {
        let params: [String: Any] = ["order":sort.rawValue,"sort":ascending ? "asc":"desc","page":page,"pageSize":20,"subtitle":subtitle ? 1:0,"includeTranslationWorks":true]
        var query = params.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
        if sort == .random { query.append(URLQueryItem(name:"seed",value:String(seed))) }
        if keyword.utf16.count > 500 {
            var body = params; body["keyword"] = keyword
            if sort == .random { body["seed"] = seed }
            return try await request("/api/search/", method: "POST", body: body)
        }
        return try await request(keyword.isEmpty ? "/api/works" : "/api/search/" + Self.encodeSegment(keyword), query: query)
    }
    func work(_ id: Int) async throws -> ASMRWork { try await request("/api/workInfo/\(id)") }
    /// Works the site recommends for this account; needs the login token.
    func recommended(uuid: String, page: Int = 1) async throws -> WorkPage {
        var body = Self.recommenderBody(page:page); body["recommenderUuid"] = uuid
        return try await request("/api/recommender/recommend-for-user", method: "POST", body: body)
    }
    /// The site's most popular works, for visitors who are not signed in.
    func popular(page: Int = 1) async throws -> WorkPage {
        try await request("/api/recommender/popular", method: "POST", body: Self.recommenderBody(page:page))
    }
    /// The site's recommender takes the same keyword syntax, so the 18+ filter applies here too.
    static func recommenderBody(page: Int) -> [String: Any] {
        let keyword = ContentFilter.query("")
        return ["keyword":keyword.isEmpty ? " " : keyword,"page":page,"pageSize":20,"subtitle":0,"localSubtitledWorks":[],"withPlaylistStatus":[]]
    }
    func tags() async throws -> [ASMRFacet] { try await request("/api/tags/") }
    func tracks(_ id: Int) async throws -> [ASMRNode] { try await request("/api/tracks/\(id)", query: [.init(name:"v",value:"2")]) }
}

/// API bodies and the login token never follow redirects onto another origin.
nonisolated final class APIOriginGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == origin.scheme, url.host == origin.host,
              (url.port ?? 443) == (origin.port ?? 443) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
