import Foundation
import Observation
import SwiftData

/// UI state that is not persisted: what is playing.
@MainActor
@Observable
final class AppModel {
    var nowPlayingKey: String?
    /// Where the current play starts when it isn't the saved position: 0 for Start Over,
    /// a bookmark or chapter time. nil resumes as usual.
    private(set) var startOverride: Double?

    func play(_ item: MediaItem, from seconds: Double? = nil) {
        startOverride = seconds
        nowPlayingKey = item.key
    }

    func item(forKey key: String, in context: ModelContext) -> MediaItem? {
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
