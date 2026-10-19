import Foundation
import SwiftData

/// A folder or a single video the user added: local, iCloud Drive or an external drive.
@Model
final class LibrarySource {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Security-scoped bookmark to the folder. Refreshed when it goes stale.
    var bookmark: Data
    var addedAt: Date
    var lastScannedAt: Date?
    /// true when the user picked one video rather than a folder. The bookmark then points at the file.
    var isFile: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.source)
    var items: [MediaItem] = []

    init(name: String, bookmark: Data, isFile: Bool = false) {
        self.id = UUID()
        self.name = name
        self.bookmark = bookmark
        self.addedAt = .now
        self.isFile = isFile
    }
}
