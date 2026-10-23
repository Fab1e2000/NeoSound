import Foundation

/// One copy of the main tracks: the site often ships the same tracks as MP3/WAV, with and without sound effects.
nonisolated struct TrackVersion: Codable, Hashable, Sendable {
    let format: String
    let withSE: Bool
}

/// A work's file tree regrouped for the detail page: main tracks by version, everything else as extras.
nonisolated struct WorkContents: Sendable {
    var main: [(version: TrackVersion, entry: TrackEntry)] = []
    var scripts: [TrackEntry] = []
    var images: [TrackEntry] = []
    var bonusAudio: [TrackEntry] = []
    var subtitles: [TrackEntry] = []
    var others: [TrackEntry] = []

    var versions: [TrackVersion] {
        main.reduce(into: []) { if !$0.contains($1.version) { $0.append($1.version) } }
    }
    var formats: [String] { versions.reduce(into: []) { if !$0.contains($1.format) { $0.append($1.format) } } }
    var hasSEChoice: Bool { Set(versions.map(\.withSE)).count > 1 }
    var hasExtras: Bool { !(scripts.isEmpty && images.isEmpty && subtitles.isEmpty && others.isEmpty) }

    func tracks(for version: TrackVersion?) -> [TrackEntry] {
        guard let version else { return [] }
        return main.filter { $0.version == version }.map(\.entry)
    }
    /// MP3 with sound effects when offered, otherwise the first version in site order.
    var defaultVersion: TrackVersion? {
        let format = formats.contains("MP3") ? "MP3" : formats.first
        return versions.first { $0.format == format && $0.withSE } ?? versions.first { $0.format == format }
    }
    /// The closest existing version after the viewer changes one of the two pickers.
    func resolve(format: String, withSE: Bool) -> TrackVersion? {
        versions.first { $0.format == format && $0.withSE == withSE } ?? versions.first { $0.format == format }
    }

    init(_ entries: [TrackEntry]) {
        for entry in entries {
            let name = entry.title.lowercased()
            let place = entry.path + "/" + entry.title
            if entry.node.type == "audio" {
                if Self.isBonus(entry.path) { bonusAudio.append(entry); continue }
                main.append((TrackVersion(format: Self.format(of: entry.title), withSE: !Self.lacksSE(place)), entry))
            } else if [".vtt", ".srt", ".lrc"].contains(where: { name.hasSuffix($0) }) {
                subtitles.append(entry)
            } else if entry.node.type == "image" {
                images.append(entry)
            } else if entry.node.type == "text" || [".txt", ".pdf"].contains(where: { name.hasSuffix($0) }) {
                scripts.append(entry)
            } else {
                others.append(entry)
            }
        }
    }

    static func format(of title: String) -> String {
        let ext = (title as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "音频" : ext
    }
    static func lacksSE(_ text: String) -> Bool {
        text.contains(/(?i)SE\s*(なし|無し|無|off|カット)|no\s*SE|効果音\s*(なし|無し)/)
    }
    static func isBonus(_ path: String) -> Bool {
        path.contains(/(?i)特典|おまけ|オマケ|bonus|omake|次回作|予告|体験版/)
    }

    /// Track number and a readable name without the extension and version markers.
    static func display(_ title: String) -> (number: String?, name: String) {
        var name = (title as NSString).deletingPathExtension
        name = name.replacing(/[_\s]*[（(]?\s*SE\s*(あり|有り|有|なし|無し|無)\s*[）)]?/, with: "")
            .replacing(/[_\s]+(MP3|WAV|FLAC|mp3|wav|flac)(?=[_\s]|$)/, with: "")
        var number: String?
        if let m = name.firstMatch(of: /^(?i)(?:トラック|track)\s*(\d{1,3})[\s_.\-、:：]*/) {
            number = String(Int(m.1) ?? 0); name = String(name[m.range.upperBound...])
        } else if let m = name.firstMatch(of: /^(?i)ex(?:\s*\d+[\s_.\-、:：]*|[\s_.\-、:：]+)/) {
            number = "EX"; name = String(name[m.range.upperBound...])
        } else if let m = name.firstMatch(of: /^(\d{1,3})[\s_.\-、:：]+/) {
            number = String(Int(m.1) ?? 0); name = String(name[m.range.upperBound...])
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "_- 　").union(.whitespaces))
        return (number, name.isEmpty ? (title as NSString).deletingPathExtension : name)
    }
}
