import Foundation
import Observation
import SwiftData

/// TitleChek: looks up films and shows on TMDB, for folders where the user turned it on, to get
/// proper titles, years, artwork, genres, cast and episode names. Only titles and years are sent.
@MainActor
@Observable
final class TitleChekService {
    /// A title TMDB didn't know is asked about again after this long.
    static let retryAfter: TimeInterval = 7 * 24 * 60 * 60

    private let context: ModelContext
    /// The TMDB client, or nil without a token. Tests swap in canned replies.
    var makeTransport: () -> (any TMDBTransport)? = { TokenStore.token.map { URLSessionTMDB(token: $0) } }
    private(set) var isRunning = false
    private(set) var checked = 0
    private(set) var toCheck = 0
    /// The last problem, shown in Settings > TitleChek.
    var lastError: String?
    private var runAgain = false

    init(context: ModelContext) {
        self.context = context
    }

    /// Matches what's new in every TitleChek folder. Titles matched before are linked without asking
    /// TMDB again; `force` asks again about everything.
    func run(force: Bool = false) async {
        guard !isRunning else { runAgain = true; return }
        guard let transport = makeTransport() else {
            lastError = TitleChekError.noToken.localizedDescription
            return
        }
        isRunning = true
        defer { isRunning = false }
        lastError = nil
        repeat {
            runAgain = false
            await pass(transport, force: force)
        } while runAgain
    }

    /// Turning it off forgets the matches for that folder; its files go back to their file names.
    func setEnabled(_ enabled: Bool, for source: LibrarySource) {
        source.titleChek = enabled
        if !enabled {
            for item in source.items { item.info = nil }
        }
        try? context.save()
        if enabled { Task { await run() } }
    }

    // MARK: Matching

    private struct Group {
        var kind: ContentKind
        var title: String
        var year: Int?
        var items: [MediaItem] = []
        var seasons: Set<Int> = []
    }

    private func pass(_ transport: any TMDBTransport, force: Bool) async {
        let sources = ((try? context.fetch(FetchDescriptor<LibrarySource>())) ?? [])
            .filter { $0.titleChek && $0.content != .homeVideos && !$0.isDeleted }
        var groups: [String: Group] = [:]
        for source in sources {
            for item in source.items where !item.isDeleted {
                let kind = item.kind
                guard let key = TitleMatcher.key(kind: kind, title: item.cleanTitle, year: item.releaseYear, show: item.showName)
                else { continue }
                let title = (kind == .film ? item.cleanTitle : item.showName) ?? ""
                var group = groups[key] ?? Group(kind: kind == .film ? .film : .episode, title: title, year: kind == .film ? item.releaseYear : nil)
                group.items.append(item)
                if kind == .episode { group.seasons.insert(item.season ?? 1) }
                groups[key] = group
            }
        }
        let known = Dictionary(((try? context.fetch(FetchDescriptor<TitleInfo>())) ?? []).map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })

        let stale = groups.filter { key, group in needsLookup(known[key], group: group, force: force) }
        toCheck = stale.count
        checked = 0
        for key in groups.keys.sorted() {
            let group = groups[key]!
            var info = known[key]
            if stale[key] != nil {
                do {
                    info = try await lookUp(key: key, group: group, existing: info, transport: transport)
                } catch {
                    lastError = (error as? TitleChekError)?.localizedDescription ?? "Couldn't reach TMDB. TitleChek will try again later."
                    try? context.save()
                    return
                }
                checked += 1
            }
            guard let info else { continue }
            for item in group.items where !item.isDeleted && item.info?.persistentModelID != info.persistentModelID {
                item.info = info
            }
            if checked % 10 == 0 { try? context.save() }
        }
        try? context.save()
    }

    private func needsLookup(_ info: TitleInfo?, group: Group, force: Bool) -> Bool {
        guard let info, !force else { return true }
        if info.notFound { return Date.now.timeIntervalSince(info.checkedAt) > Self.retryAfter }
        return !group.seasons.isSubset(of: info.fetchedSeasons)
    }

    private func lookUp(key: String, group: Group, existing: TitleInfo?, transport: any TMDBTransport) async throws -> TitleInfo {
        let info = existing ?? {
            let info = TitleInfo(key: key, mediaType: group.kind == .film ? "movie" : "tv")
            context.insert(info)
            return info
        }()
        info.checkedAt = .now
        let decoder = TMDB.decoder

        if group.kind == .film {
            guard let id = try await findFilm(group.title, year: group.year, transport: transport) else {
                info.notFound = true
                return info
            }
            if info.tmdbID != id || existing == nil || info.notFound {
                let details = try decoder.decode(TMDB.MovieDetails.self, from: try await transport.get("movie/\(id)", query: ["append_to_response": "credits"]))
                info.tmdbID = id
                info.title = details.title
                info.year = TMDB.year(details.releaseDate)
                info.overview = details.overview
                info.genresRaw = (details.genres ?? []).map(\.name).joined(separator: "|")
                info.directorsRaw = (details.credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name).joined(separator: "|")
                info.castRaw = (details.credits?.cast ?? []).prefix(6).map(\.name).joined(separator: "|")
                info.collectionName = details.belongsToCollection?.name
                info.rating = details.voteAverage
                info.posterFile = await image(details.posterPath, size: "w500", name: "tmdb-movie-\(id)-poster", transport: transport)
                info.backdropFile = await image(details.backdropPath, size: "w1280", name: "tmdb-movie-\(id)-backdrop", transport: transport)
            }
        } else {
            guard let id = try await findShow(group.title, transport: transport) else {
                info.notFound = true
                return info
            }
            if info.tmdbID != id || existing == nil || info.notFound {
                let details = try decoder.decode(TMDB.ShowDetails.self, from: try await transport.get("tv/\(id)", query: ["append_to_response": "credits"]))
                info.tmdbID = id
                info.title = details.name
                info.year = TMDB.year(details.firstAirDate)
                info.overview = details.overview
                info.genresRaw = (details.genres ?? []).map(\.name).joined(separator: "|")
                info.directorsRaw = (details.createdBy ?? []).map(\.name).joined(separator: "|")
                info.castRaw = (details.credits?.cast ?? []).prefix(6).map(\.name).joined(separator: "|")
                info.rating = details.voteAverage
                info.posterFile = await image(details.posterPath, size: "w500", name: "tmdb-tv-\(id)-poster", transport: transport)
                info.backdropFile = await image(details.backdropPath, size: "w1280", name: "tmdb-tv-\(id)-backdrop", transport: transport)
                info.fetchedSeasons = []
                info.episodeNames = [:]
            }
            var names = info.episodeNames
            var fetched = info.fetchedSeasons
            for season in group.seasons.subtracting(fetched).sorted() {
                // A season TMDB doesn't list (a special, a mis-numbered folder) is just skipped.
                if let data = try? await transport.get("tv/\(id)/season/\(season)", query: [:]),
                   let found = try? decoder.decode(TMDB.Season.self, from: data) {
                    for episode in found.episodes { if let name = episode.name { names["\(season)-\(episode.episodeNumber)"] = name } }
                }
                fetched.insert(season)
            }
            info.episodeNames = names
            info.fetchedSeasons = fetched
        }
        info.notFound = false
        return info
    }

    private func findFilm(_ title: String, year: Int?, transport: any TMDBTransport) async throws -> Int? {
        var attempts: [[String: String]] = [["query": title, "include_adult": "false"]]
        if let year { attempts.insert(["query": title, "include_adult": "false", "year": String(year)], at: 0) }
        for query in attempts {
            let results = try TMDB.decoder.decode(TMDB.SearchResults<TMDB.MovieResult>.self, from: try await transport.get("search/movie", query: query)).results
            let candidates = results.map {
                TitleMatcher.Candidate(id: $0.id, titles: [$0.title, $0.originalTitle].compactMap { $0 }, year: TMDB.year($0.releaseDate), popularity: $0.popularity ?? 0)
            }
            if let id = TitleMatcher.best(candidates, title: title, year: year) { return id }
        }
        return nil
    }

    private func findShow(_ title: String, transport: any TMDBTransport) async throws -> Int? {
        let results = try TMDB.decoder.decode(TMDB.SearchResults<TMDB.ShowResult>.self, from: try await transport.get("search/tv", query: ["query": title, "include_adult": "false"])).results
        let candidates = results.map {
            TitleMatcher.Candidate(id: $0.id, titles: [$0.name, $0.originalName].compactMap { $0 }, year: TMDB.year($0.firstAirDate), popularity: $0.popularity ?? 0)
        }
        return TitleMatcher.best(candidates, title: title, year: nil)
    }

    /// Downloads artwork into the thumbnail cache once; nil when TMDB has none or it didn't arrive.
    private func image(_ path: String?, size: String, name: String, transport: any TMDBTransport) async -> String? {
        guard let path else { return nil }
        let file = name + ".jpg"
        if ThumbnailService.exists(file) { return file }
        guard let data = try? await transport.image(path, size: size), !data.isEmpty,
              (try? data.write(to: ThumbnailService.directory.appending(path: file))) != nil
        else { return nil }
        return file
    }
}
