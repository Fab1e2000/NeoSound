import Foundation
import Observation

/// App-wide site state: the API client on the chosen host and one-off messages for the user.
@Observable
final class ASMRStore {
    let client: ASMRClient
    var message: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, client: ASMRClient? = nil) {
        self.defaults = defaults
        let host = defaults.string(forKey:"apiHost") ?? ASMRClient.hosts[0]
        self.client = client ?? ASMRClient(baseURL: URL(string: ASMRClient.hosts.contains(host) ? host : ASMRClient.hosts[0])!)
        // Retired preferences and the removed account feature's cached user.
        for key in ["allowedTags", "blockedTags", "excludedTags", "preferSmall", "asmrBookmarks", "sessionUser", "sessionUserKey"] {
            defaults.removeObject(forKey:key)
        }
    }
    /// Drops a login token left in the Keychain by the removed account feature.
    static func removeRetiredLoginToken() { try? TokenVault.save(nil, account:"token") }
    func changeHost(_ host: String) {
        guard ASMRClient.hosts.contains(host), let url = URL(string: host), client.baseURL != url else { return }
        client.baseURL = url; defaults.set(host, forKey:"apiHost")
    }
    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
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
