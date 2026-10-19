import Foundation
import Observation
import SwiftData
import SwiftUI

/// UI state that is not persisted: what is playing and where the user is.
@MainActor
@Observable
final class AppModel {
    var nowPlayingKey: String?
    /// The current play-through ignores saved progress.
    private(set) var playsFromStart = false
    var path = NavigationPath()
    /// Bumped when the logo is pressed on Home, which then scrolls back to the top.
    private(set) var homeRequests = 0

    func play(_ item: MediaItem, fromStart: Bool = false) {
        playsFromStart = fromStart
        nowPlayingKey = item.key
    }

    /// The logo: back to Home from a detail page, or to the top of Home when already there.
    func goHome() {
        if path.isEmpty {
            homeRequests += 1
        } else {
            path = NavigationPath()
        }
    }

    func item(forKey key: String, in context: ModelContext) -> MediaItem? {
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
