import Foundation
import Observation
import SwiftData

/// UI state that is not persisted: what is playing.
@MainActor
@Observable
final class AppModel {
    var nowPlayingKey: String?

    func play(_ item: MediaItem) {
        nowPlayingKey = item.key
    }

    func item(forKey key: String, in context: ModelContext) -> MediaItem? {
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
