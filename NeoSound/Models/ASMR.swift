import Foundation

nonisolated struct ASMRWork: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var source_id: String?
    var name: String?
    var circle: ASMRFacet?
    var tags: [ASMRFacet]?
    var vas: [ASMRFacet]?
    var release: String?
    var nsfw: Bool?
    var duration: Double?
    var rate_average_2dp: Double?
    var mainCoverUrl: URL?
    var thumbnailCoverUrl: URL?
    var rate_count: Int?
    var dl_count: Int?
    var age_category_string: String?
    var source_url: String?
    var language_editions: [LanguageEdition]?
    var rate_count_detail: [RatingBucket]?
    var sourceID: String { source_id ?? String(format: "RJ%08d", id) }
    var creator: String? { circle?.name ?? name }
    var coverURL: URL? { mainCoverUrl ?? thumbnailCoverUrl }
}

/// Optional site metadata decodes leniently so an odd field never drops the whole work.
nonisolated struct LanguageEdition: Codable, Hashable, Sendable {
    var lang: String?
    var label: String?
    var workno: String?
    enum CodingKeys: String, CodingKey { case lang, label, workno }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lang = try? c.decode(String.self, forKey: .lang)
        label = try? c.decode(String.self, forKey: .label)
        workno = try? c.decode(String.self, forKey: .workno)
    }
}
nonisolated struct RatingBucket: Codable, Hashable, Sendable {
    var review_point: Int?
    var count: Int?
    var ratio: Int?
    enum CodingKeys: String, CodingKey { case review_point, count, ratio }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        review_point = try? c.decode(Int.self, forKey: .review_point)
        count = try? c.decode(Int.self, forKey: .count)
        ratio = try? c.decode(Int.self, forKey: .ratio)
    }
}

nonisolated struct ASMRFacet: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let count: Int?
    init(id: String, name: String, count: Int? = nil) { self.id = id; self.name = name; self.count = count }
    enum CodingKeys: String, CodingKey { case id, name, count }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeFlexibleID(forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
    }
}

nonisolated struct ASMRNode: Decodable, Hashable, Sendable {
    let type: String
    let title: String
    let hash: String?
    let children: [ASMRNode]?
    let mediaStreamUrl: URL?
    let mediaDownloadUrl: URL?
    let streamLowQualityUrl: URL?
    let duration: Double?
    let size: Int64?
    enum CodingKeys: String, CodingKey { case type, title, hash, children, mediaStreamUrl, mediaDownloadUrl, streamLowQualityUrl, duration, size }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        children = try c.decodeIfPresent([ASMRNode].self, forKey: .children)
        func url(_ key: CodingKeys) throws -> URL? {
            guard let s = try c.decodeIfPresent(String.self, forKey: key), !s.isEmpty,
                  let u = URL(string: s), u.scheme == "https", u.host != nil else { return nil }
            return u
        }
        mediaStreamUrl = try url(.mediaStreamUrl); mediaDownloadUrl = try url(.mediaDownloadUrl)
        streamLowQualityUrl = try url(.streamLowQualityUrl)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
    }
    /// The file's own stream; the low-quality copy is used only when the site offers no original stream.
    var streamURL: URL? { mediaStreamUrl ?? streamLowQualityUrl }
}

/// IDs are scoped by work and directory position; folder titles are not globally unique.
nonisolated struct TrackEntry: Identifiable, Hashable, Sendable {
    let id: String
    let node: ASMRNode
    let path: String
    var title: String { node.title }
    var duration: Double? { node.duration }
    static func flatten(_ nodes: [ASMRNode], workID: Int, prefix: String = "", position: String = "") -> [TrackEntry] {
        nodes.enumerated().flatMap { index, node in
            let coordinate = position + "/\(index)"
            if node.type == "folder" {
                return flatten(node.children ?? [], workID: workID, prefix: prefix.isEmpty ? node.title : prefix + "/" + node.title, position: coordinate)
            }
            return [TrackEntry(id: "\(workID):\(coordinate):\(node.hash ?? node.title)", node: node, path: prefix)]
        }
    }
}
nonisolated struct PlayingTrack: Identifiable, Hashable, Sendable {
    let item: ASMRWork
    let track: TrackEntry
    var id: String { track.id }
}
nonisolated struct WorkPage: Decodable, Sendable {
    let works: [ASMRWork]
    let pagination: Pagination
}
nonisolated struct Pagination: Decodable, Sendable {
    let currentPage: Int
    let pageSize: Int
    let totalCount: Int
    var hasNext: Bool { currentPage * pageSize < totalCount }
}
extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleID(forKey key: Key) throws -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        return String(try decode(Int.self, forKey: key))
    }
}
nonisolated enum WorkSort: String, CaseIterable, Identifiable, Sendable {
    case create_date, release, rating, dl_count, rate_average_2dp, random
    var id: String { rawValue }
    var title: String {
        switch self {
        case .create_date: "最新收录"
        case .release: "发行日期"
        case .rating: "热度"
        case .dl_count: "销量"
        case .rate_average_2dp: "评分"
        case .random: "随机"
        }
    }
}
