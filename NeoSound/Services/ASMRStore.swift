import Foundation
import Observation
import CryptoKit

@Observable
final class ASMRStore {
    let client: ASMRClient
    private(set) var user: ASMRUser?
    private(set) var sessionRevision = 0
    private(set) var reviewRevision = 0
    var message: String?
    var accountBusy = false
    var preferSmall: Bool { didSet { defaults.set(preferSmall, forKey: "preferSmall") } }
    private let defaults: UserDefaults
    private let saveToken: (String?) throws -> Void
    private var refreshingSession = false
    private var lastSessionCheck: Date?
    var loggedIn: Bool { client.token != nil && user?.loggedIn != false }
    private var sessionCacheKey: String? {
        guard let token = client.token else { return nil }
        return SHA256.hash(data:Data((client.baseURL.absoluteString + token).utf8)).map { String(format:"%02x",$0) }.joined()
    }
    private func cacheUser() {
        defaults.set(try? JSONEncoder().encode(user),forKey:"sessionUser")
        defaults.set(sessionCacheKey,forKey:"sessionUserKey")
    }
    init(defaults: UserDefaults = .standard, client: ASMRClient? = nil, saveToken: @escaping (String?) throws -> Void = { try TokenVault.save($0) }) {
        self.saveToken = saveToken
        self.defaults = defaults
        let host = defaults.string(forKey:"apiHost") ?? ASMRClient.hosts[0]
        self.client = client ?? ASMRClient(baseURL: URL(string: ASMRClient.hosts.contains(host) ? host : ASMRClient.hosts[0])!, token: TokenVault.read())
        for key in ["allowedTags", "blockedTags", "excludedTags"] { defaults.removeObject(forKey:key) }
        preferSmall = defaults.object(forKey:"preferSmall") as? Bool ?? true
        defaults.removeObject(forKey:"asmrBookmarks") // Retired test-only local favorites.
        if let key = sessionCacheKey, defaults.string(forKey:"sessionUserKey") == key,
           let data = defaults.data(forKey:"sessionUser") {
            user = try? JSONDecoder().decode(ASMRUser.self,from:data)
        }
        self.client.onAuthenticationFailure = { [weak self] in
            guard let self else { return }
            do {
                try self.logout()
                self.message = "登录已失效，请重新登录。"
            } catch { self.message = error.localizedDescription }
        }
    }
    func refreshSession() async {
        guard client.token != nil, !accountBusy, !refreshingSession else { return }
        if let lastSessionCheck, Date().timeIntervalSince(lastSessionCheck) < 300 { return }
        let revision = sessionRevision
        let token = client.token
        refreshingSession = true
        defer { refreshingSession = false }
        do {
            let response: AuthResponse = try await client.request("/api/auth/me")
            try Task.checkCancellation()
            guard revision == sessionRevision, token == client.token else { return }
            if response.user.loggedIn == false {
                try logout()
                message = "登录已失效，请重新登录。"
            } else if response.user.loggedIn == true {
                // Accept a renewed token if the server supplies one; never invent a refresh endpoint.
                if let renewed = response.token, !renewed.isEmpty {
                    try saveToken(renewed)
                    client.token = renewed
                }
                user = response.user
                cacheUser()
                lastSessionCheck = Date()
            }
        } catch {
            // Offline, timeouts and server failures do not erase the saved session.
            // The client invalidates only authentication failures belonging to this session.
        }
    }
    func login(name: String, password: String) async throws {
        let revision = sessionRevision
        accountBusy = true; defer { accountBusy = false }
        let response: AuthResponse = try await client.request("/api/auth/me", method:"POST", body:["name":name,"password":password], sendToken:false)
        guard revision == sessionRevision else { throw CancellationError() }
        guard let token = response.token, !token.isEmpty else { throw ASMRAPIError.invalidResponse }
        try saveToken(token)
        client.token = token; user = response.user; sessionRevision += 1
        cacheUser(); lastSessionCheck = Date()
    }
    func logout() throws {
        try saveToken(nil); client.token = nil; user = nil; sessionRevision += 1
        lastSessionCheck = nil
        defaults.removeObject(forKey:"sessionUser")
        defaults.removeObject(forKey:"sessionUserKey")
    }
    func changeHost(_ host: String) throws {
        guard ASMRClient.hosts.contains(host), let url = URL(string: host), client.baseURL != url else { return }
        try logout() // Tokens do not silently move to another origin.
        client.baseURL = url; defaults.set(host, forKey:"apiHost")
    }
    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
    }
    func saveReview(workID: Int, rating: Int, text: String, progress: String) async throws {
        let revision = sessionRevision
        _ = try await client.data("/api/review",method:"PUT",body:["work_id":workID,"rating":rating == 0 ? NSNull() : rating as Any,"review_text":text,"progress":progress],authenticated:true)
        guard revision == sessionRevision else { throw CancellationError() }
        reviewRevision += 1
    }

}

@Observable
final class WorkFeed {
    private(set) var works: [ASMRWork] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var page = 0
    private(set) var total = 0
    private(set) var hasNext = false
    /// Consecutive pages whose works were all filtered out; automatic paging pauses after a few.
    private(set) var emptyPages = 0
    var pausedOnFilteredPages: Bool { emptyPages >= 3 }
    private var generation = 0
    func clear() { generation += 1; works = []; loading = false; page = 0; total = 0; hasNext = false; error = nil; emptyPages = 0 }
    func load(reset: Bool, automatically: Bool = false, fetch: (Int) async throws -> WorkPage) async {
        if automatically && (error != nil || pausedOnFilteredPages) { return }
        if !reset && (loading || !hasNext) { return }
        generation += 1; let ticket = generation
        loading = true; error = nil
        if !automatically { emptyPages = 0 } // A manual request resumes automatic paging.
        let requestedPage = reset ? 1 : page + 1
        do {
            let response = try await fetch(requestedPage)
            try Task.checkCancellation()
            guard generation == ticket else { return }
            var seen = Set<Int>()
            let visible = response.works.filter(ContentFilter.allows)
            emptyPages = visible.isEmpty && !response.works.isEmpty ? (reset ? 1 : emptyPages + 1) : 0
            works = ((reset ? [] : works) + visible).filter { seen.insert($0.id).inserted }
            page = response.pagination.currentPage; total = response.pagination.totalCount
            hasNext = response.pagination.hasNext
        } catch {
            guard generation == ticket else { return }
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
        }
        if generation == ticket { loading = false }
    }
}

nonisolated struct PlaylistPage: Decodable, Sendable {
    let playlists: [ASMRPlaylist]
    let pagination: Pagination
}
extension ASMRClient {
    func playlists(page: Int = 1, filter: String = "all") async throws -> PlaylistPage {
        try await request("/api/playlist/get-playlists", query:[.init(name:"page",value:String(page)),.init(name:"pageSize",value:"20"),.init(name:"filterBy",value:filter)], authenticated:true)
    }
    func mutatePlaylist(_ operation: String, body: [String: Any]) async throws {
        _ = try await data("/api/playlist/" + operation, method:"POST", body:body, authenticated:true)
    }
}
