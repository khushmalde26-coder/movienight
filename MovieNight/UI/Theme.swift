import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let accent = Color(red: 0.98, green: 0.78, blue: 0.35)   // warm "movie night" amber
    static let secondaryText = Color.white.opacity(0.6)

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
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func date(_ date: Date?) -> String? {
        date?.formatted(date: .long, time: .omitted)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
