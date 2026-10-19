import SwiftUI

enum Theme {
    // Taken from the logo: ink #0B0B0B, light #F5F5F7, play-button grey #8E8E93.
    static let background = Color(red: 0.043, green: 0.043, blue: 0.043)
    static let accent = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let secondaryText = Color(red: 0.557, green: 0.557, blue: 0.576)

    #if os(macOS)
    static let cardWidth: CGFloat = 280
    static let heroHeight: CGFloat = 480
    static let gutter: CGFloat = 48
    #else
    static let cardWidth: CGFloat = 220
    static let heroHeight: CGFloat = 360
    static let gutter: CGFloat = 20
    #endif
}

enum Formatters {
    /// "1h 32m", "3m 12s", "45s": how long something is.
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return secs > 0 && minutes < 10 ? "\(minutes)m \(secs)s" : "\(minutes)m" }
        return "\(secs)s"
    }

    /// "32m left"
    static func remaining(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 30 else { return nil }
        return duration(seconds).map { "\($0) left" }
    }

    /// Clock-style length for the stamp on a card ("12:04"), nil when unknown.
    static func clockLength(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return clock(seconds.rounded())
    }

    /// "1:02:03" or "4:05": for the player's time labels.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func date(_ date: Date?) -> String? {
        date?.formatted(date: .long, time: .omitted)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
