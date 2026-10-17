import Foundation

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
