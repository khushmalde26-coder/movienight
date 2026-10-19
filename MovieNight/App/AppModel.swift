import Foundation
import Observation
import SwiftData

/// UI state that is not persisted: what is playing.
@MainActor
@Observable
final class AppModel {
    var nowPlayingKey: String?
    var tab: AppTab = .home
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

/// The app's main sections: a sidebar on iPad and Mac, tabs on narrow screens.
enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, films, tvShows, homeVideos, library, collections, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .films: "Films"
        case .tvShows: "TV Shows"
        case .homeVideos: "Home Videos"
        case .library: "Library"
        case .collections: "Collections"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .films: "film"
        case .tvShows: "tv"
        case .homeVideos: "video"
        case .library: "square.grid.2x2"
        case .collections: "rectangle.stack"
        case .settings: "gearshape"
        }
    }
}
