import Foundation

/// 目录快照。字段命名与参考设计的 JSON 契约一致（snake_case）。
nonisolated struct CatalogSnapshot: Decodable, Sendable {
    let schemaVersion: Int
    let snapshotId: String
    let items: [CatalogItem]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case snapshotId = "snapshot_id"
        case items
        case nextCursor = "next_cursor"
    }
}

nonisolated struct CatalogItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let namespace: String
    let title: String
    let creator: String?
    let category: Category
    let summary: String
    let revision: String
    let artwork: ArtworkStyle
    let tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case id = "item_id"
        case namespace = "source_namespace"
        case title, creator, category, summary
        case revision = "content_revision"
        case artwork = "artwork_style"
        case tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeNonEmpty(String.self, forKey: .id)
        namespace = try c.decodeNonEmpty(String.self, forKey: .namespace)
        title = try c.decodeNonEmpty(String.self, forKey: .title)
        creator = try c.decodeIfPresent(String.self, forKey: .creator)
        category = try c.decode(Category.self, forKey: .category)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        revision = try c.decodeNonEmpty(String.self, forKey: .revision)
        artwork = try c.decodeIfPresent(ArtworkStyle.self, forKey: .artwork) ?? .unknown
        tracks = try c.decode([Track].self, forKey: .tracks)
    }

    init(id: String, namespace: String, title: String, creator: String?, category: Category,
         summary: String, revision: String, artwork: ArtworkStyle, tracks: [Track]) {
        self.id = id
        self.namespace = namespace
        self.title = title
        self.creator = creator
        self.category = category
        self.summary = summary
        self.revision = revision
        self.artwork = artwork
        self.tracks = tracks
    }

    /// 所有音轨已知时长之和；任一未知则返回 nil，不用 0 冒充。
    var totalDuration: TimeInterval? {
        var total: TimeInterval = 0
        for track in tracks {
            guard let d = track.duration else { return nil }
            total += d
        }
        return total
    }
}

nonisolated struct Track: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let itemId: String
    let revision: String
    let title: String
    let durationMs: Int?
    let delivery: Delivery
    let subtitles: [SubtitleRef]

    enum CodingKeys: String, CodingKey {
        case id = "track_id"
        case itemId = "item_id"
        case revision, title
        case durationMs = "duration_ms"
        case delivery, subtitles
    }

    enum Delivery: String, Decodable, Sendable {
        case progressive
        case hlsVod = "hls_vod"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeNonEmpty(String.self, forKey: .id)
        itemId = try c.decodeNonEmpty(String.self, forKey: .itemId)
        revision = try c.decodeNonEmpty(String.self, forKey: .revision)
        title = try c.decodeNonEmpty(String.self, forKey: .title)
        // 可空但必须出现：缺键视为契约错误。
        guard c.contains(.durationMs) else {
            throw DecodingError.keyNotFound(CodingKeys.durationMs, .init(codingPath: c.codingPath, debugDescription: "duration_ms 必须出现，可为 null"))
        }
        durationMs = try c.decodeNil(forKey: .durationMs) ? nil : c.decode(Int.self, forKey: .durationMs)
        if let ms = durationMs, ms < 0 {
            throw DecodingError.dataCorruptedError(forKey: .durationMs, in: c, debugDescription: "duration_ms 不能为负数")
        }
        delivery = try c.decode(Delivery.self, forKey: .delivery)
        subtitles = try c.decode([SubtitleRef].self, forKey: .subtitles)
    }

    init(id: String, itemId: String, revision: String, title: String, durationMs: Int?,
         delivery: Delivery = .progressive, subtitles: [SubtitleRef] = []) {
        self.id = id
        self.itemId = itemId
        self.revision = revision
        self.title = title
        self.durationMs = durationMs
        self.delivery = delivery
        self.subtitles = subtitles
    }

    var duration: TimeInterval? { durationMs.map { TimeInterval($0) / 1000 } }
}

nonisolated struct SubtitleRef: Decodable, Hashable, Sendable {
    let id: String
    let language: String
    let format: Format

    enum Format: String, Decodable, Sendable { case webvtt, srt, lrc }
}

nonisolated enum Category: String, Decodable, CaseIterable, Sendable {
    case rain, noise, nature, calm, breath

    var label: String {
        switch self {
        case .rain: "雨声"
        case .noise: "白噪音"
        case .nature: "自然"
        case .calm: "轻音乐"
        case .breath: "冥想"
        }
    }
}

nonisolated enum ArtworkStyle: String, Decodable, Sendable {
    case rain, waves, forest, fire, noise, breath, storm, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ArtworkStyle(rawValue: raw) ?? .unknown
    }
}

extension KeyedDecodingContainer {
    nonisolated func decodeNonEmpty(_ type: String.Type, forKey key: Key) throws -> String {
        let value = try decode(String.self, forKey: key)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(key.stringValue) 不能为空")
        }
        return value
    }
}

nonisolated enum DurationFormat {
    /// 12:04 / 1:02:03
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 30 分钟 / 1.5 小时
    static func label(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "时长未知" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) 分钟" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) 小时" : String(format: "%.1f 小时", hours)
    }
}
