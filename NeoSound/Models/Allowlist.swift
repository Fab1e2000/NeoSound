import Foundation

/// 服务端签发的白名单。客户端只拿到决定、版本、有效期与资源绑定；审核证据留在审核系统。
nonisolated struct Allowlist: Decodable, Sendable {
    let schemaVersion: Int
    let version: Int
    let generatedAt: Date
    let validUntil: Date
    var entries: [AllowlistEntry]
    var revokedTrackIds: Set<String>

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case version = "allowlist_version"
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case entries
        case revokedTrackIds = "revoked_track_ids"
    }

    init(schemaVersion: Int = 1, version: Int, generatedAt: Date, validUntil: Date,
         entries: [AllowlistEntry], revokedTrackIds: Set<String> = []) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.generatedAt = generatedAt
        self.validUntil = validUntil
        self.entries = entries
        self.revokedTrackIds = revokedTrackIds
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

nonisolated struct AllowlistEntry: Decodable, Hashable, Sendable {
    let namespace: String
    let itemId: String
    let trackId: String
    let revision: String
    let decision: Decision
    let policyVersion: String

    enum CodingKeys: String, CodingKey {
        case namespace = "source_namespace"
        case itemId = "item_id"
        case trackId = "track_id"
        case revision, decision
        case policyVersion = "policy_version"
    }
}

/// 审核结论。不认识的值一律落到 `.unknown`，并在准入时拒绝。
nonisolated enum Decision: Hashable, Sendable, Decodable {
    case approved
    case pendingReview
    case rejected
    case revoked
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "approved": self = .approved
        case "pending_review": self = .pendingReview
        case "rejected": self = .rejected
        case "revoked": self = .revoked
        default: self = .unknown(raw)
        }
    }
}
