import Foundation
import Observation
import CryptoKit

/// App-wide site state: the API client on the chosen host, the signed-in account and one-off messages.
@Observable
final class ASMRStore {
    static let tokenAccount = "session"
    let client: ASMRClient
    private(set) var user: ASMRUser?
    var message: String?
    private(set) var accountBusy = false
    /// Bumped on every login and logout, so a reply from an older session is ignored.
    private var sessionRevision = 0
    private let defaults: UserDefaults
    private let saveToken: (String?) throws -> Void
    private var refreshingSession = false
    private var lastSessionCheck: Date?
    var loggedIn: Bool { client.token != nil && user?.loggedIn != false }
    /// The cached account belongs to this host and token only.
    private var sessionCacheKey: String? {
        guard let token = client.token else { return nil }
        return SHA256.hash(data:Data((client.baseURL.absoluteString + token).utf8)).map { String(format:"%02x",$0) }.joined()
    }
    init(defaults: UserDefaults = .standard, client: ASMRClient? = nil,
         readToken: () -> String? = { TokenVault.read(account:ASMRStore.tokenAccount) },
         saveToken: @escaping (String?) throws -> Void = { try TokenVault.save($0,account:ASMRStore.tokenAccount) }) {
        self.defaults = defaults; self.saveToken = saveToken
        let host = defaults.string(forKey:"apiHost") ?? ASMRClient.hosts[0]
        self.client = client ?? ASMRClient(baseURL: URL(string: ASMRClient.hosts.contains(host) ? host : ASMRClient.hosts[0])!, token:readToken())
        // Retired preferences.
        for key in ["allowedTags", "blockedTags", "excludedTags", "preferSmall", "asmrBookmarks"] {
            defaults.removeObject(forKey:key)
        }
        if let key = sessionCacheKey, defaults.string(forKey:"sessionUserKey") == key, let data = defaults.data(forKey:"sessionUser") {
            user = try? JSONDecoder().decode(ASMRUser.self,from:data)
        }
        self.client.onAuthenticationFailure = { [weak self] in
            guard let self else { return }
            do { try self.logout(); self.message = "登录已失效，请重新登录。" } catch { self.message = error.localizedDescription }
        }
    }
    /// Drops the login token an earlier build kept under the old Keychain account.
    static func removeRetiredLoginToken() { try? TokenVault.save(nil, account:"token") }

    func login(name: String, password: String) async throws {
        let revision = sessionRevision
        accountBusy = true; defer { accountBusy = false }
        let response: AuthResponse = try await client.request("/api/auth/me",method:"POST",body:["name":name,"password":password],sendToken:false)
        guard revision == sessionRevision else { throw CancellationError() }
        guard let token = response.token, !token.isEmpty else { throw ASMRAPIError.invalidResponse }
        try saveToken(token)
        client.token = token; user = response.user; sessionRevision += 1
        cacheUser(); lastSessionCheck = .now
    }
    func logout() throws {
        try saveToken(nil); client.token = nil; user = nil; sessionRevision += 1
        lastSessionCheck = nil
        defaults.removeObject(forKey:"sessionUser"); defaults.removeObject(forKey:"sessionUserKey")
    }
    /// Signs in with a token from a backup; the next session check verifies it.
    func restore(token: String) throws {
        guard client.token == nil, !token.isEmpty else { return }
        try saveToken(token)
        client.token = token; sessionRevision += 1; lastSessionCheck = nil
    }
    /// Checks the saved session at most every five minutes. Offline and server errors keep it;
    /// only the server saying the token is no longer valid signs out.
    func refreshSession() async {
        guard client.token != nil, !accountBusy, !refreshingSession else { return }
        if let lastSessionCheck, Date.now.timeIntervalSince(lastSessionCheck) < 300 { return }
        let revision = sessionRevision, token = client.token
        refreshingSession = true; defer { refreshingSession = false }
        do {
            let response: AuthResponse = try await client.request("/api/auth/me")
            try Task.checkCancellation()
            guard revision == sessionRevision, token == client.token else { return }
            if response.user.loggedIn == false {
                try logout(); message = "登录已失效，请重新登录。"
            } else if response.user.loggedIn == true {
                // Accept a renewed token if the server supplies one; never invent a refresh endpoint.
                if let renewed = response.token, !renewed.isEmpty { try saveToken(renewed); client.token = renewed }
                user = response.user; cacheUser(); lastSessionCheck = .now
            }
        } catch {}
    }
    /// The token belongs to the host it was issued by, so switching hosts signs out.
    func changeHost(_ host: String) throws {
        guard ASMRClient.hosts.contains(host), let url = URL(string: host), client.baseURL != url else { return }
        if client.token != nil { try logout() }
        client.baseURL = url; defaults.set(host, forKey:"apiHost")
    }
    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
    }
    private func cacheUser() {
        defaults.set(try? JSONEncoder().encode(user),forKey:"sessionUser")
        defaults.set(sessionCacheKey,forKey:"sessionUserKey")
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
