import Foundation

nonisolated enum SubtitleMatcher {
    /// Prefer a sibling with the same filename, then a unique match across version/language folders.
    /// Never assign the only subtitle in a multi-track work to every track.
    static func match(_ track: TrackEntry, in entries: [TrackEntry]) -> TrackEntry? {
        let subtitles = WorkContents(entries).subtitles.filter {
            $0.node.mediaStreamUrl != nil || $0.node.mediaDownloadUrl != nil
        }
        let named = subtitles.filter { stem($0.title) == stem(track.title) }
        let siblings = named.filter { $0.path == track.path }
        if siblings.count == 1 { return siblings.first }
        if named.count == 1 { return named.first }
        if let number = WorkContents.display(track.title).number {
            let numbered = subtitles.filter { WorkContents.display($0.title).number == number }
            if numbered.count == 1 { return numbered.first }
        }
        if entries.filter({ $0.node.type == "audio" }).count == 1, subtitles.count == 1 {
            return subtitles.first
        }
        return nil
    }

    private static func stem(_ title: String) -> String {
        var value = (title as NSString).deletingPathExtension.lowercased()
        if ["mp3", "wav", "flac", "m4a"].contains((value as NSString).pathExtension) {
            value = (value as NSString).deletingPathExtension
        }
        return value.trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
