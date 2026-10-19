import Foundation
import SwiftData
import Testing
@testable import MovieNight

/// Canned TMDB replies keyed by path plus sorted query, e.g. "search/movie?query=Heat&year=1995".
final class StubTMDB: TMDBTransport, @unchecked Sendable {
    private let replies: [String: String]
    private let lock = NSLock()
    private var _requests: [String] = []
    var requests: [String] { lock.withLock { _requests } }

    init(_ replies: [String: String]) { self.replies = replies }

    func get(_ path: String, query: [String: String]) async throws -> Data {
        let query = query.filter { $0.key != "include_adult" }
        let key = query.isEmpty ? path : path + "?" + query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        lock.withLock { _requests.append(key) }
        guard let reply = replies[key] else {
            if path.hasPrefix("search/") { return Data(#"{"results":[]}"#.utf8) }
            throw TitleChekError.server(404)
        }
        return Data(reply.utf8)
    }

    func image(_ path: String, size: String) async throws -> Data { throw TitleChekError.server(404) }
}

struct TitleMatcherTests {
    @Test func normalisesTitlesSoSmallDifferencesMatch() {
        #expect(TitleMatcher.normalize("Schindler's List") == TitleMatcher.normalize("Schindlers List"))
        #expect(TitleMatcher.normalize("Ocean’s Eleven") == "oceans eleven")
        #expect(TitleMatcher.normalize("The Fast & the Furious") == "fast and the furious")
        #expect(TitleMatcher.normalize("Amélie") == "amelie")
        #expect(TitleMatcher.normalize("Spider-Man: No Way Home") == "spider man no way home")
    }

    @Test func prefersAnExactTitleWithTheRightYear() {
        let candidates = [
            TitleMatcher.Candidate(id: 1, titles: ["Dune: Part Two"], year: 2024, popularity: 900),
            TitleMatcher.Candidate(id: 2, titles: ["Dune"], year: 1984, popularity: 40),
            TitleMatcher.Candidate(id: 3, titles: ["Dune"], year: 2021, popularity: 300),
        ]
        #expect(TitleMatcher.best(candidates, title: "Dune", year: 2021) == 3)
        #expect(TitleMatcher.best(candidates, title: "Dune", year: 1984) == 2)
        // No year: the more popular exact match.
        #expect(TitleMatcher.best(candidates, title: "Dune", year: nil) == 3)
    }

    @Test func fallsBackToTheTopResultUnlessTheYearsDisagree() {
        let candidates = [TitleMatcher.Candidate(id: 7, titles: ["Star Wars"], year: 1977, popularity: 100)]
        #expect(TitleMatcher.best(candidates, title: "Star Wars Episode IV A New Hope", year: nil) == 7)
        #expect(TitleMatcher.best(candidates, title: "Star Wars Episode IV A New Hope", year: 1978) == 7)
        #expect(TitleMatcher.best(candidates, title: "Star Wars Episode IV A New Hope", year: 1997) == nil)
        #expect(TitleMatcher.best([], title: "Anything", year: nil) == nil)
    }

    @Test func keysOneTitleInfoPerFilmAndPerShowAndNoneForHomeVideos() {
        #expect(TitleMatcher.key(kind: .film, title: "The Matrix", year: 1999, show: nil) == "film|matrix|1999")
        #expect(TitleMatcher.key(kind: .episode, title: "x", year: nil, show: "The Wire") == "tv|wire")
        #expect(TitleMatcher.key(kind: .extra, title: "x", year: nil, show: "The Wire") == "tv|wire")
        #expect(TitleMatcher.key(kind: .homeVideo, title: "Beach", year: nil, show: nil) == nil)
    }

    @Test func decodesTMDBDetails() throws {
        let details = try TMDB.decoder.decode(TMDB.MovieDetails.self, from: Data(TitleChekFixtures.heatDetails.utf8))
        #expect(details.title == "Heat")
        #expect(TMDB.year(details.releaseDate) == 1995)
        #expect(details.belongsToCollection == nil)
        #expect(details.credits?.crew?.first { $0.job == "Director" }?.name == "Michael Mann")
        let season = try TMDB.decoder.decode(TMDB.Season.self, from: Data(TitleChekFixtures.wireSeason1.utf8))
        #expect(season.episodes.map(\.episodeNumber) == [1, 2])
    }
}

@MainActor
struct TitleChekServiceTests {
    private func library() throws -> (ModelContainer, LibrarySource) {
        let container = try ModelContainer(for: LibrarySource.self, MediaItem.self, WatchRecord.self, SavedMoment.self, TitleInfo.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let source = LibrarySource(name: "Films", bookmark: Data())
        source.content = .filmsAndTV
        source.titleChek = true
        container.mainContext.insert(source)
        func add(_ path: String, kind: ContentKind, title: String, year: Int? = nil, show: String? = nil, season: Int? = nil, episode: Int? = nil) {
            let item = MediaItem(key: "s/\(path)", relativePath: path, collection: "", fileName: path, fileSize: 1, fileCreatedAt: nil)
            item.kindRaw = kind.rawValue
            item.cleanTitle = title
            item.releaseYear = year
            item.showName = show
            item.season = season
            item.episodeNumber = episode
            item.source = source
            container.mainContext.insert(item)
        }
        add("Heat (1995).mkv", kind: .film, title: "Heat", year: 1995)
        add("Heat (1995) copy.mkv", kind: .film, title: "Heat", year: 1995)
        add("Nothing Like It.mkv", kind: .film, title: "Nothing Like It")
        add("The Wire S1E1.mkv", kind: .episode, title: "The Wire", show: "The Wire", season: 1, episode: 1)
        add("The Wire S1E2.mkv", kind: .episode, title: "The Wire", show: "The Wire", season: 1, episode: 2)
        add("Beach.mov", kind: .homeVideo, title: "Beach")
        try container.mainContext.save()
        return (container, source)
    }

    @Test func matchesFilmsAndShowsOnceAndLeavesHomeVideosAlone() async throws {
        let (container, source) = try library()
        let stub = StubTMDB(TitleChekFixtures.replies)
        let service = TitleChekService(context: container.mainContext)
        service.makeTransport = { stub }
        await service.run()
        #expect(service.lastError == nil)

        let items = Dictionary(uniqueKeysWithValues: source.items.map { ($0.relativePath, $0) })
        let heat = try #require(items["Heat (1995).mkv"])
        #expect(heat.info?.tmdbID == 949)
        #expect(heat.info?.directors == ["Michael Mann"])
        #expect(heat.info?.genres == ["Action", "Crime", "Drama"])
        #expect(heat.browseEntry.genres == ["Action", "Crime", "Drama"])
        // Both copies share one TitleInfo.
        #expect(items["Heat (1995) copy.mkv"]?.info?.persistentModelID == heat.info?.persistentModelID)

        let episode = try #require(items["The Wire S1E2.mkv"])
        #expect(episode.info?.title == "The Wire")
        #expect(episode.resolvedEpisodeTitle == "The Detail")
        #expect(episode.episodeLabel == "S1 E2 · The Detail")
        #expect(items["Beach.mov"]?.info == nil)
        #expect(items["Nothing Like It.mkv"]?.info?.notFound == true)
        #expect(items["Nothing Like It.mkv"]?.displayTitle == "Nothing Like It")
        #expect(!stub.requests.contains { $0.contains("Beach") })

        // Nothing new: no more requests (the unknown film waits a week).
        let count = stub.requests.count
        await service.run()
        #expect(stub.requests.count == count)

        // Turning it off goes back to the file names.
        service.setEnabled(false, for: source)
        #expect(heat.info == nil)
    }

    @Test func withoutATokenItSaysWhereToAddOne() async throws {
        let (container, source) = try library()
        let service = TitleChekService(context: container.mainContext)
        service.makeTransport = { nil }
        await service.run()
        #expect(service.lastError == TitleChekError.noToken.localizedDescription)
        #expect(source.items.allSatisfy { $0.info == nil })
    }

    @Test func aRejectedTokenStopsAndSaysSo() async throws {
        let (container, _) = try library()
        struct Rejecting: TMDBTransport {
            func get(_ path: String, query: [String: String]) async throws -> Data { throw TitleChekError.rejected }
            func image(_ path: String, size: String) async throws -> Data { throw TitleChekError.rejected }
        }
        let service = TitleChekService(context: container.mainContext)
        service.makeTransport = { Rejecting() }
        await service.run()
        #expect(service.lastError == TitleChekError.rejected.localizedDescription)
    }
}

struct MatchedShelfTests {
    private func film(_ key: String, year: Int?, genres: [String] = [], directors: [String] = [], collection: String? = nil, franchise: String? = nil) -> BrowseEntry {
        BrowseEntry(key: key, title: key, fileName: key, collection: "", sourceID: nil, sourceName: "", isFileSource: false,
                    date: nil, addedAt: .distantPast, duration: 7200, progressFraction: 0, isFinished: true, kind: .film,
                    franchise: franchise, genres: genres, directors: directors, tmdbCollection: collection, year: year)
    }

    @Test func buildsGenreDecadeDirectorAndCollectionRows() {
        let films = [
            film("Heat", year: 1995, genres: ["Crime", "Drama"], directors: ["Michael Mann"]),
            film("Collateral", year: 2004, genres: ["Crime", "Thriller"], directors: ["Michael Mann"]),
            film("Se7en", year: 1995, genres: ["Crime", "Mystery"], directors: ["David Fincher"]),
            film("Toy Story", year: 1995, genres: ["Animation"], directors: ["John Lasseter"], collection: "Toy Story Collection"),
            film("Toy Story 2", year: 1999, genres: ["Animation"], directors: ["John Lasseter"], collection: "Toy Story Collection"),
            film("Dr No", year: 1962, collection: "James Bond Collection", franchise: "007"),
            film("Goldfinger", year: 1964, collection: "James Bond Collection", franchise: "007"),
            film("Up", year: 2009, genres: ["Animation"]),
            film("Ratatouille", year: 2007, genres: ["Animation"]),
        ]
        let shelves = FilmShelves.build(films)
        let titles = shelves.map(\.title)
        #expect(titles.contains("Toy Story Collection"))
        // 007 is already a folder row.
        #expect(!titles.contains("James Bond Collection"))
        #expect(shelves.first { $0.kind == .genre("Crime") }?.itemKeys == ["Collateral", "Se7en", "Heat"])
        #expect(titles.contains("Animation"))
        #expect(!titles.contains("Drama"))                       // only one film
        #expect(shelves.first { $0.kind == .decade(1990) }?.itemKeys == ["Heat", "Se7en", "Toy Story", "Toy Story 2"])
        #expect(titles.contains("Directed by Michael Mann"))
        #expect(titles.contains("Directed by John Lasseter"))
        #expect(!titles.contains("Directed by David Fincher"))
    }

    @Test func noDecadeRowsWhenEverythingIsFromOneDecade() {
        let films = (0..<4).map { film("F\($0)", year: 2010 + $0) }
        #expect(!FilmShelves.build(films).contains { if case .decade = $0.kind { true } else { false } })
    }
}

enum TitleChekFixtures {
    static let heatDetails = #"""
    {"id":949,"title":"Heat","release_date":"1995-12-15","overview":"Obsessive master thief Neil McCauley leads a crew.",
     "genres":[{"id":28,"name":"Action"},{"id":80,"name":"Crime"},{"id":18,"name":"Drama"}],
     "poster_path":"/heat.jpg","backdrop_path":"/heatwide.jpg","belongs_to_collection":null,"vote_average":7.9,
     "credits":{"cast":[{"name":"Al Pacino"},{"name":"Robert De Niro"}],
                "crew":[{"name":"Michael Mann","job":"Director"},{"name":"Dante Spinotti","job":"Director of Photography"}]}}
    """#

    static let wireSeason1 = #"""
    {"episodes":[{"episode_number":1,"name":"The Target"},{"episode_number":2,"name":"The Detail"}]}
    """#

    static let replies: [String: String] = [
        "search/movie?query=Heat&year=1995": #"{"results":[{"id":949,"title":"Heat","release_date":"1995-12-15","popularity":40},{"id":5,"title":"Heat","release_date":"1986-03-14","popularity":3}]}"#,
        "movie/949?append_to_response=credits": heatDetails,
        "search/tv?query=The Wire": #"{"results":[{"id":1438,"name":"The Wire","first_air_date":"2002-06-02","popularity":90}]}"#,
        "tv/1438?append_to_response=credits": #"{"id":1438,"name":"The Wire","first_air_date":"2002-06-02","overview":"Baltimore.","genres":[{"name":"Crime"},{"name":"Drama"}],"created_by":[{"name":"David Simon"}],"credits":{"cast":[{"name":"Dominic West"}]}}"#,
        "tv/1438/season/1": wireSeason1,
    ]
}
