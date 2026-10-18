import Foundation

/// All-ages filter. The site's search syntax excludes 18+ works on the server (`$-age:adult$`,
/// verified to return only general and R15 works); `allows` stays as a client-side safety net.
nonisolated enum ContentFilter {
    static let excludeAdult = "$-age:adult$"
    /// Adds the server-side 18+ exclusion to a site search keyword (an empty keyword lists everything allowed).
    static func query(_ keyword: String) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? excludeAdult : trimmed + " " + excludeAdult
    }
    static func allows(_ work: ASMRWork) -> Bool { work.nsfw != true }
}
