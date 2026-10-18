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

/// Anonymous client for the site's public API; covers and media are fetched separately from the URLs it returns.
@Observable final class ASMRClient {
    static let hosts = ["https://api.asmr-200.com", "https://api.asmr.one", "https://api.asmr-100.com", "https://api.asmr-300.com"]
    var baseURL: URL
    private let session: URLSession
    init(baseURL: URL = URL(string: hosts[0])!, session: URLSession = .shared) {
        self.baseURL = baseURL; self.session = session
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
    func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await data(path, query: query, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func data(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var r = URLRequest(url: try Self.makeURL(base: baseURL, path: path, query: query))
        r.httpMethod = method; r.timeoutInterval = 25
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: r, delegate: APIOriginGuard(origin:baseURL))
        guard let http = response as? HTTPURLResponse else { throw ASMRAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["error"] as? String ?? "请求失败，请稍后重试"
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
    func tracks(_ id: Int) async throws -> [ASMRNode] { try await request("/api/tracks/\(id)", query: [.init(name:"v",value:"2")]) }
}

/// Request bodies never follow redirects onto another origin.
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
