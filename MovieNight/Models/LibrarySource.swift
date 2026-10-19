import Foundation
import SwiftData

/// A folder the user added: local, iCloud Drive or an external drive.
@Model
final class LibrarySource {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Security-scoped bookmark to the folder. Refreshed when it goes stale.
    var bookmark: Data
    var addedAt: Date
    var lastScannedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.source)
    var items: [MediaItem] = []

    init(name: String, bookmark: Data) {
        self.id = UUID()
        self.name = name
        self.bookmark = bookmark
        self.addedAt = .now
    }
}
