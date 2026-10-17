import Foundation

nonisolated struct SubtitleCue: Hashable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// 最小 WebVTT 解析：只取时间与纯文本，丢弃样式标签；有上限，解析失败的 cue 直接跳过。
nonisolated enum WebVTT {
    static let maxBytes = 512 * 1024
    static let maxCues = 5_000

    static func parse(_ data: Data) -> [SubtitleCue] {
        guard data.count <= maxBytes, let text = String(data: data, encoding: .utf8) else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("WEBVTT") || normalized.hasPrefix("\u{FEFF}WEBVTT") else { return [] }

        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = timestamp(parts[0]),
                  let end = timestamp(parts[1].split(separator: " ").first.map(String.init) ?? ""),
                  end > start else { continue }
            let body = lines[(timingIndex + 1)...].joined(separator: "\n")
            let plain = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            guard !plain.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: String(plain.prefix(200))))
            if cues.count >= maxCues { break }
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func activeCue(in cues: [SubtitleCue], at time: TimeInterval) -> SubtitleCue? {
        cues.last { $0.start <= time && time < $0.end }
    }

    /// 00:01:02.500 或 01:02.500
    static func timestamp(_ raw: String) -> TimeInterval? {
        let fields = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        var total: TimeInterval = 0
        for field in fields {
            guard let v = TimeInterval(field), v >= 0 else { return nil }
            total = total * 60 + v
        }
        return total
    }
}

extension WebVTT {
    nonisolated static func parseSubtitle(_ data: Data, filename: String) -> [SubtitleCue] {
        guard data.count <= maxBytes, let text = String(data:data, encoding:.utf8) else { return [] }
        if filename.lowercased().hasSuffix(".srt") {
            let normalized = text.replacingOccurrences(of:"\r\n",with:"\n")
                .replacingOccurrences(of:",",with:".")
            return parse(Data(("WEBVTT\n\n" + normalized).utf8))
        }
        if filename.lowercased().hasSuffix(".lrc") {
            guard let regex = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\](.*)"#) else { return [] }
            let ns = text as NSString
            let values = regex.matches(in:text, range:NSRange(location:0,length:ns.length)).compactMap { match -> (Double,String)? in
                guard let minutes = Double(ns.substring(with:match.range(at:1))), let seconds = Double(ns.substring(with:match.range(at:2))) else { return nil }
                return (minutes * 60 + seconds, ns.substring(with:match.range(at:3)))
            }.sorted { $0.0 < $1.0 }
            return values.enumerated().map { index, value in
                SubtitleCue(start:value.0,end:index + 1 < values.count ? values[index + 1].0 : value.0 + 15,text:value.1)
            }
        }
        return parse(data)
    }
}
