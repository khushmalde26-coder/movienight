import Foundation

/// What the cleanup suggestions look at, as a value so the logic is pure and tested.
struct HealthInput: Sendable, Hashable {
    var key: String
    var fileName: String
    var fileSize: Int64
    var duration: Double?
    var isPlayable: Bool?
    var isLocal: Bool
}

/// Suggestions only: nothing here deletes or changes files.
struct LibraryHealth: Sendable, Equatable {
    /// Groups of two or more copies of the same video.
    var duplicates: [[String]] = []
    /// Neither player could open these.
    var unplayable: [String] = []
    /// iCloud files that aren't on this device, so they have no artwork or length yet.
    var notDownloaded: [String] = []

    var count: Int { duplicates.count + unplayable.count + notDownloaded.count }

    /// Sizes below this are iCloud placeholders, so they can't identify a copy.
    static let minimumComparableSize: Int64 = 1_000_000

    static func check(_ items: [HealthInput]) -> LibraryHealth {
        var health = LibraryHealth()
        // The same bytes under two paths: same size and same length, whatever the names.
        // Without a length yet, fall back to same name and same size.
        let comparable = items.filter { $0.fileSize >= minimumComparableSize }
        let groups = Dictionary(grouping: comparable) { item -> String in
            if let duration = item.duration { return "size:\(item.fileSize)|length:\(Int(duration.rounded()))" }
            return "size:\(item.fileSize)|name:\(item.fileName.lowercased())"
        }
        health.duplicates = groups.values
            .filter { $0.count > 1 }
            .map { $0.map(\.key).sorted() }
            .sorted { $0[0] < $1[0] }
        health.unplayable = items.filter { $0.isPlayable == false }.map(\.key).sorted()
        health.notDownloaded = items.filter { !$0.isLocal }.map(\.key).sorted()
        return health
    }
}
