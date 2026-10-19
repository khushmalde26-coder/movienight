import Foundation

/// A TV show built from its episode files: seasons in order, extras apart, and where you're up to.
struct TVShowSummary: Identifiable, Sendable, Hashable {
    var name: String
    /// Episodes in watching order (season, then episode).
    var episodeKeys: [String]
    var seasons: [Int]
    var extraKeys: [String]
    /// The episode to play next: the one you're partway through, or the one after the last you finished.
    var nextKey: String?
    /// When anything in the show was last played; nil if never.
    var lastPlayedAt: Date?
    var latestAddedAt: Date
    var id: String { name }
}

enum TVLibrary {
    static func shows(_ entries: [BrowseEntry]) -> [TVShowSummary] {
        let byShow = Dictionary(grouping: entries.filter { ($0.kind == .episode || $0.kind == .extra) && $0.show != nil }) { $0.show! }
        return byShow.compactMap { name, members -> TVShowSummary? in
            let episodes = members.filter { $0.kind == .episode }
                .sorted { ($0.season ?? 1, $0.episode ?? 0, $0.key) < ($1.season ?? 1, $1.episode ?? 0, $1.key) }
            guard !episodes.isEmpty else { return nil }
            return TVShowSummary(
                name: name,
                episodeKeys: episodes.map(\.key),
                seasons: Array(Set(episodes.map { $0.season ?? 1 })).sorted(),
                extraKeys: members.filter { $0.kind == .extra }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map(\.key),
                nextKey: nextEpisode(episodes),
                lastPlayedAt: episodes.compactMap(\.lastPlayedAt).max(),
                latestAddedAt: episodes.map(\.addedAt).max() ?? .distantPast
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Partway through one? That one. Otherwise the first unfinished episode after the last one you
    /// watched; a show you've never started begins at the first episode.
    static func nextEpisode(_ episodes: [BrowseEntry]) -> String? {
        if let current = episodes.filter({ !$0.isFinished && $0.progressFraction > 0.02 && $0.lastPlayedAt != nil })
            .max(by: { $0.lastPlayedAt! < $1.lastPlayedAt! }) {
            return current.key
        }
        let lastWatched = episodes.lastIndex { $0.isFinished || $0.lastPlayedAt != nil }
        let start = lastWatched.map { $0 + 1 } ?? 0
        return episodes[start...].first { !$0.isFinished }?.key
    }
}

enum FilmShelves {
    static let epicMinimum: TimeInterval = 150 * 60

    /// Films in release order when every one has a year, otherwise by title ("Rocky", "Rocky II").
    static func ordered(_ films: [BrowseEntry]) -> [BrowseEntry] {
        if films.allSatisfy({ $0.date != nil }) {
            return films.sorted { ($0.date!, $0.key) < ($1.date!, $1.key) }
        }
        return films.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func build(_ entries: [BrowseEntry], now: Date = .now) -> [Shelf] {
        let films = entries.filter { $0.kind == .film }
        guard !films.isEmpty else { return [] }
        var shelves: [Shelf] = []

        let recent = films.filter { now.timeIntervalSince($0.addedAt) < ShelfBuilder.recentlyAddedWindow }
            .sorted { $0.addedAt > $1.addedAt }
        if !recent.isEmpty && recent.count < films.count {
            shelves.append(Shelf(kind: .recentlyAdded, title: "Recently Added", itemKeys: recent.prefix(30).map(\.key)))
        }
        let unwatched = films.filter { !$0.isFinished && $0.progressFraction <= 0.02 }
        if !unwatched.isEmpty && unwatched.count < films.count {
            shelves.append(Shelf(kind: .unwatched, title: "Unwatched", itemKeys: ordered(unwatched).map(\.key)))
        }
        let franchises = Dictionary(grouping: films.filter { $0.franchise != nil }) { $0.franchise! }
        for name in franchises.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            shelves.append(Shelf(kind: .franchise(name), title: name, itemKeys: ordered(franchises[name]!).map(\.key)))
        }
        shelves += matchedShelves(films, franchises: franchises)
        let uhd = films.filter(\.isUHD)
        if uhd.count >= 2 && uhd.count < films.count {
            shelves.append(Shelf(kind: .uhd, title: "In 4K", itemKeys: ordered(uhd).map(\.key)))
        }
        let epics = films.filter { ($0.duration ?? 0) >= epicMinimum }.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        if epics.count >= 2 && epics.count < films.count {
            shelves.append(Shelf(kind: .epics, title: "Epics", itemKeys: epics.map(\.key)))
        }
        return shelves
    }

    static let genreMinimum = 3
    static let maximumGenreRows = 6
    static let decadeMinimum = 3
    static let directorMinimum = 2

    /// Rows that need TitleChek data (decades also use years from file names): TMDB's collections
    /// that no folder already groups, the biggest genres, decades and directors with a few films each.
    static func matchedShelves(_ films: [BrowseEntry], franchises: [String: [BrowseEntry]]) -> [Shelf] {
        var shelves: [Shelf] = []
        let folderSets = Set(franchises.values.map { Set($0.map(\.key)) })
        let folderNames = Set(franchises.keys.map(TitleMatcher.normalize))
        let collections = Dictionary(grouping: films.filter { $0.tmdbCollection != nil }) { $0.tmdbCollection! }
        for name in collections.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let members = collections[name]!
            let shortName = name.replacingOccurrences(of: #"\s+Collection$"#, with: "", options: .regularExpression)
            guard members.count >= 2, !folderSets.contains(Set(members.map(\.key))),
                  !folderNames.contains(TitleMatcher.normalize(shortName)) else { continue }
            shelves.append(Shelf(kind: .tmdbCollection(name), title: name, itemKeys: ordered(members).map(\.key)))
        }

        var byGenre: [String: [BrowseEntry]] = [:]
        for film in films { for genre in film.genres { byGenre[genre, default: []].append(film) } }
        let genres = byGenre.filter { $0.value.count >= genreMinimum && $0.value.count < films.count }
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .prefix(maximumGenreRows)
        for (genre, members) in genres {
            shelves.append(Shelf(kind: .genre(genre), title: genre, itemKeys: members.sorted(by: newestFirst).map(\.key)))
        }

        let decades = Dictionary(grouping: films.filter { $0.year != nil }) { $0.year! / 10 * 10 }
            .filter { $0.value.count >= decadeMinimum }
        if decades.count >= 2 {
            for decade in decades.keys.sorted(by: >) {
                shelves.append(Shelf(kind: .decade(decade), title: "The \(decade)s", itemKeys: ordered(decades[decade]!).map(\.key)))
            }
        }

        var byDirector: [String: [BrowseEntry]] = [:]
        for film in films { for director in film.directors { byDirector[director, default: []].append(film) } }
        for director in byDirector.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
        where byDirector[director]!.count >= directorMinimum {
            shelves.append(Shelf(kind: .director(director), title: "Directed by \(director)", itemKeys: ordered(byDirector[director]!).map(\.key)))
        }
        return shelves
    }

    private static func newestFirst(_ a: BrowseEntry, _ b: BrowseEntry) -> Bool {
        (a.year ?? 0, a.key) > (b.year ?? 0, b.key)
    }
}

/// The mixed front page: what you're in the middle of, what's next, what's new, then a few rows that change daily.
enum HomeShelves {
    static func build(_ entries: [BrowseEntry], homeVideos: [ShelfInput], now: Date = .now,
                      calendar: Calendar = .current, highlights: Int = 4) -> [Shelf] {
        var shelves: [Shelf] = []
        // Episodes go in Next Up instead, one per show.
        let watching = entries
            .filter { $0.kind != .episode && $0.kind != .extra && !$0.isFinished && $0.progressFraction > 0.02 && $0.lastPlayedAt != nil }
            .sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
        if !watching.isEmpty {
            shelves.append(Shelf(kind: .continueWatching, title: "Continue Watching", itemKeys: watching.prefix(20).map(\.key)))
        }
        let next = TVLibrary.shows(entries).filter { $0.lastPlayedAt != nil && $0.nextKey != nil }
            .sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
        if !next.isEmpty {
            shelves.append(Shelf(kind: .nextUp, title: "Next Up", itemKeys: next.compactMap(\.nextKey)))
        }

        // New things, with a show's batch of new episodes counted once: its earliest new episode,
        // placed where the show's newest arrival would be.
        let fresh = entries.filter { $0.kind != .extra && now.timeIntervalSince($0.addedAt) < ShelfBuilder.recentlyAddedWindow }
        let newEpisodes = Dictionary(grouping: fresh.filter { $0.kind == .episode && $0.show != nil }) { $0.show! }
        let showCards = newEpisodes.values.map { episodes -> (entry: BrowseEntry, addedAt: Date) in
            let first = episodes.min { ($0.season ?? 1, $0.episode ?? 0) < ($1.season ?? 1, $1.episode ?? 0) }!
            return (first, episodes.map(\.addedAt).max()!)
        }
        let others = fresh.filter { !($0.kind == .episode && $0.show != nil) }.map { ($0, $0.addedAt) }
        let recent = (others + showCards).sorted { ($0.addedAt, $0.entry.key) > ($1.addedAt, $1.entry.key) }.map(\.entry)
        let mainCount = entries.filter { $0.kind != .extra }.count
        if !recent.isEmpty && recent.count < mainCount {
            shelves.append(Shelf(kind: .recentlyAdded, title: "Recently Added", itemKeys: recent.prefix(30).map(\.key)))
        }

        // Rotating highlights: today's memories always lead; the rest take turns day by day.
        var candidates = FilmShelves.build(entries, now: now).filter { $0.kind != .recentlyAdded }
        let homeShelves = ShelfBuilder.build(homeVideos, now: now, calendar: calendar)
        if let memories = homeShelves.first(where: { $0.kind == .onThisDay }) {
            shelves.append(memories)
        }
        if let latestYear = homeShelves.first(where: { if case .year = $0.kind { true } else { false } }) {
            candidates.append(Shelf(kind: latestYear.kind, title: "Home Videos from \(latestYear.title)", itemKeys: latestYear.itemKeys))
        }
        if !candidates.isEmpty {
            let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
            let start = day % candidates.count
            let rotated = Array(candidates[start...] + candidates[..<start])
            shelves += rotated.prefix(highlights).map { Shelf(kind: $0.kind, title: $0.title, itemKeys: Array($0.itemKeys.prefix(20))) }
        }
        return shelves
    }

    /// The banner: a memory from this date, else a film that changes daily, else anything.
    static func heroKey(_ entries: [BrowseEntry], homeVideos: [ShelfInput], now: Date = .now, calendar: Calendar = .current) -> String? {
        if let memory = ShelfBuilder.onThisDay(homeVideos.filter { !$0.isVertical }, now: now, calendar: calendar).first {
            return memory.key
        }
        let films = entries.filter { $0.kind == .film }.map(\.key).sorted()
        let pool = films.isEmpty ? entries.filter { $0.kind != .extra }.map(\.key).sorted() : films
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return pool[day % pool.count]
    }
}
