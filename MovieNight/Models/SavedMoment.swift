import Foundation
import SwiftData

/// A timestamp the user bookmarked while watching.
@Model
final class SavedMoment {
    /// MediaItem.key of the video.
    var itemKey: String
    var seconds: Double
    var createdAt: Date

    init(itemKey: String, seconds: Double) {
        self.itemKey = itemKey
        self.seconds = seconds
        self.createdAt = .now
    }
}

/// A chapter marker read from the file (MP4/MOV chapter tracks, MKV chapters).
struct Chapter: Codable, Hashable, Sendable {
    var title: String
    var start: Double
}
