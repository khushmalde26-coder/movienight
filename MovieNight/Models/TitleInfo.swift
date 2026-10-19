import Foundation
import SwiftData

/// What TitleChek found on TMDB for one film or one TV show, shared by every file that's that title.
@Model
final class TitleInfo {
    /// TitleMatcher.key: "film|<title>|<year>" or "tv|<show>".
    var key: String
    var tmdbID: Int?
    /// "movie" or "tv".
    var mediaType: String
    var title: String?
    var year: Int?
    var overview: String?
    /// Joined with "|".
    var genresRaw: String = ""
    var directorsRaw: String = ""
    var castRaw: String = ""
    /// TMDB's own franchise set, e.g. "James Bond Collection".
    var collectionName: String?
    var rating: Double?
    /// Cached artwork, stored next to the frame thumbnails.
    var posterFile: String?
    var backdropFile: String?
    /// JSON [String: String] of "season-episode" → episode name, for shows.
    var episodeNamesData: Data?
    /// Seasons whose episode names were fetched, joined with "|".
    var fetchedSeasonsRaw: String = ""
    var checkedAt: Date
    /// No match on TMDB; tried again after a week.
    var notFound: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \MediaItem.info)
    var items: [MediaItem] = []

    init(key: String, mediaType: String) {
        self.key = key
        self.mediaType = mediaType
        self.checkedAt = .now
    }

    var genres: [String] { genresRaw.isEmpty ? [] : genresRaw.components(separatedBy: "|") }
    var directors: [String] { directorsRaw.isEmpty ? [] : directorsRaw.components(separatedBy: "|") }
    var cast: [String] { castRaw.isEmpty ? [] : castRaw.components(separatedBy: "|") }

    var fetchedSeasons: Set<Int> {
        get { Set(fetchedSeasonsRaw.split(separator: "|").compactMap { Int($0) }) }
        set { fetchedSeasonsRaw = newValue.sorted().map(String.init).joined(separator: "|") }
    }

    var episodeNames: [String: String] {
        get { episodeNamesData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set { episodeNamesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    func episodeName(season: Int, episode: Int) -> String? {
        episodeNames["\(season)-\(episode)"]
    }
}
