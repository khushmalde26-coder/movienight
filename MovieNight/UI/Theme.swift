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
