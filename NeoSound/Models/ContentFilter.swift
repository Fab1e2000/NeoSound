import Foundation

/// All-ages filter: hides works the site rates 18+ (`nsfw`); general and R15 works stay visible.
nonisolated enum ContentFilter {
    static func allows(_ work: ASMRWork) -> Bool { work.nsfw != true }
}
