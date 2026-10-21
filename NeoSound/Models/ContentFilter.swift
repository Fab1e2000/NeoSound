import Foundation

/// The 18+ filter, on unless R18 is enabled in settings. The site's search syntax excludes 18+ works on the
/// server (`$-age:adult$`, verified to return only general and R15 works); `allows` stays as a client-side safety net.
/// With R18 enabled nothing is filtered.
nonisolated enum ContentFilter {
    static let excludeAdult = "$-age:adult$"
    static let storageKey = "allowsAdultContent"
    /// Off by default; set by the settings switch.
    static var allowsAdult: Bool { UserDefaults.standard.bool(forKey:storageKey) }
    /// Adds the server-side 18+ exclusion to a site search keyword (an empty keyword lists everything allowed).
    static func query(_ keyword: String, allowsAdult: Bool = allowsAdult) -> String {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        if allowsAdult { return trimmed }
        return trimmed.isEmpty ? excludeAdult : trimmed + " " + excludeAdult
    }
    static func allows(_ work: ASMRWork, allowsAdult: Bool = allowsAdult) -> Bool { allowsAdult || work.nsfw != true }
}
