import Foundation

/// 准入被拒的原因。任何缺失、冲突、过期或未知都落到这里。
nonisolated enum AdmissionDenial: Error, Hashable, Sendable {
    case allowlistMissing
    case allowlistExpired
    case notListed
    case revisionMismatch
    case notApproved(Decision)
    case revoked

    var userMessage: String {
        switch self {
        case .notApproved(.pendingReview), .notListed: "审核中，暂时不能播放"
        case .revoked, .notApproved(.revoked): "已下架，暂时不能播放"
        case .revisionMismatch: "内容已更新，等待重新审核"
        case .allowlistMissing, .allowlistExpired: "需要联网更新后才能播放"
        case .notApproved: "暂时不能播放"
        }
    }
}

/// 通过准入的凭证。只有 `AdmissionService` 能构造，播放链路只接受这个类型。
nonisolated struct AdmittedTrack: Hashable, Sendable {
    let item: CatalogItem
    let track: Track
    let allowlistVersion: Int

    fileprivate init(item: CatalogItem, track: Track, allowlistVersion: Int) {
        self.item = item
        self.track = track
        self.allowlistVersion = allowlistVersion
    }
}

/// 允许播放 = 白名单有效 ∧ 作品与音轨匹配 ∧ 版本匹配 ∧ 审核通过 ∧ 未撤销。
nonisolated struct AdmissionService: Sendable {
    let allowlist: Allowlist?
    let now: @Sendable () -> Date

    init(allowlist: Allowlist?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.allowlist = allowlist
        self.now = now
    }

    func evaluate(_ track: Track, in item: CatalogItem) -> Result<AdmittedTrack, AdmissionDenial> {
        guard let allowlist else { return .failure(.allowlistMissing) }
        guard now() < allowlist.validUntil else { return .failure(.allowlistExpired) }
        guard track.itemId == item.id else { return .failure(.notListed) }
        if allowlist.revokedTrackIds.contains(track.id) { return .failure(.revoked) }

        let candidates = allowlist.entries.filter {
            $0.namespace == item.namespace && $0.itemId == item.id && $0.trackId == track.id
        }
        guard !candidates.isEmpty else { return .failure(.notListed) }
        guard let entry = candidates.first(where: { $0.revision == track.revision }) else {
            return .failure(.revisionMismatch)
        }
        guard entry.decision == .approved else { return .failure(.notApproved(entry.decision)) }
        return .success(AdmittedTrack(item: item, track: track, allowlistVersion: allowlist.version))
    }

    func isPlayable(_ track: Track, in item: CatalogItem) -> Bool {
        if case .success = evaluate(track, in: item) { return true }
        return false
    }
}
