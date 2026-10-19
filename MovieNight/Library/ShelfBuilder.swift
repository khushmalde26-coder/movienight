import Foundation

/// A value snapshot of a MediaItem, so shelf logic is pure and testable.
struct ShelfInput: Sendable, Hashable {
    var key: String
    var collection: String
    var date: Date?
    var addedAt: Date
    var progressFraction: Double
    var duration: Double? = nil
    var isVertical: Bool = false
    var lastPlayedAt: Date?
    var isFinished: Bool
}

struct Shelf: Identifiable, Sendable, Equatable {
    enum Kind: Hashable, Sendable {
        case continueWatching
        case onThisDay
        case recentlyAdded
        case longVideos
        case quickClips
        case collection(String)
        case year(Int)
        case undated
        case nextUp
        case unwatched
        case uhd
        case epics
        case franchise(String)
    }

    var kind: Kind
    var title: String
    var itemKeys: [String]
    var id: Kind { kind }
}

enum ShelfBuilder {
    static let recentlyAddedWindow: TimeInterval = 30 * 24 * 3600
    static let onThisDayToleranceDays = 3
    /// Films, full recitals, a whole wedding: long enough to sit down for.
    static let longVideoMinimum: TimeInterval = 40 * 60
    static let quickClipMaximum: TimeInterval = 60

    static func build(_ items: [ShelfInput], now: Date = .now, calendar: Calendar = .current) -> [Shelf] {
        var shelves: [Shelf] = []
        let newestFirst: (ShelfInput, ShelfInput) -> Bool = { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        let inProgress = items
            .filter { !$0.isFinished && $0.progressFraction > 0.02 && $0.lastPlayedAt != nil }
            .sorted { $0.lastPlayedAt! > $1.lastPlayedAt! }
        if !inProgress.isEmpty {
            shelves.append(Shelf(kind: .continueWatching, title: "Continue Watching", itemKeys: inProgress.prefix(20).map(\.key)))
        }

        let memories = onThisDay(items, now: now, calendar: calendar)
        if !memories.isEmpty {
            shelves.append(Shelf(kind: .onThisDay, title: "On This Day", itemKeys: memories.map(\.key)))
        }

        // On first import everything is "recent", which would just duplicate the library.
        let recent = items
            .filter { now.timeIntervalSince($0.addedAt) < recentlyAddedWindow }
            .sorted { $0.addedAt > $1.addedAt }
        if !recent.isEmpty && recent.count < items.count {
            shelves.append(Shelf(kind: .recentlyAdded, title: "Recently Added", itemKeys: recent.prefix(30).map(\.key)))
        }

        // Duration-based rows only appear when they say something the rest of the page doesn't.
        let long = items.filter { ($0.duration ?? 0) >= longVideoMinimum }.sorted(by: newestFirst)
        if long.count >= 2 && long.count < items.count {
            shelves.append(Shelf(kind: .longVideos, title: "Feature Length", itemKeys: long.map(\.key)))
        }

        let byCollection = Dictionary(grouping: items.filter { !$0.collection.isEmpty }, by: \.collection)
        for name in byCollection.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let group = byCollection[name]!
            // A folder holding the whole library is not a useful shelf.
            guard group.count < items.count else { continue }
            shelves.append(Shelf(kind: .collection(name), title: name, itemKeys: group.sorted(by: newestFirst).map(\.key)))
        }

        let dated = items.filter { $0.date != nil }
        let byYear = Dictionary(grouping: dated) { calendar.component(.year, from: $0.date!) }
        for year in byYear.keys.sorted(by: >) {
            shelves.append(Shelf(kind: .year(year), title: String(year), itemKeys: byYear[year]!.sorted(by: newestFirst).map(\.key)))
        }

        let quick = items.filter { ($0.duration ?? .infinity) < quickClipMaximum }.sorted(by: newestFirst)
        if quick.count >= 3 && quick.count < items.count {
            shelves.append(Shelf(kind: .quickClips, title: "Quick Clips", itemKeys: quick.prefix(40).map(\.key)))
        }

        let undated = items.filter { $0.date == nil }
        if !undated.isEmpty {
            shelves.append(Shelf(kind: .undated, title: "Undated", itemKeys: undated.sorted { $0.addedAt > $1.addedAt }.map(\.key)))
        }
        return shelves
    }

    /// Home keeps the rows worth opening the app for: what you're watching, today's memories, what's new,
    /// then a few highlights. Everything else is a tap away in Library and Collections.
    static func homeShelves(_ shelves: [Shelf], highlights: Int = 3) -> [Shelf] {
        let primary = shelves.filter { [.continueWatching, .onThisDay, .recentlyAdded].contains($0.kind) }
        func first(_ match: (Shelf.Kind) -> Bool) -> Shelf? { shelves.first { match($0.kind) } }
        let candidates: [Shelf?] = [
            first { $0 == .longVideos },
            first { if case .year = $0 { true } else { false } },   // the most recent year
            first { $0 == .quickClips },
            first { if case .collection = $0 { true } else { false } },
        ]
        return primary + candidates.compactMap { $0 }.prefix(highlights)
    }

    /// Clips shot within a few days of today's date in earlier years, newest year first.
    static func onThisDay(_ items: [ShelfInput], now: Date, calendar: Calendar) -> [ShelfInput] {
        let today = calendar.dateComponents([.month, .day], from: now)
        let thisYear = calendar.component(.year, from: now)

        return items.filter { item in
            guard let date = item.date else { return false }
            let year = calendar.component(.year, from: date)
            guard year < thisYear,
                  let anchor = calendar.date(from: DateComponents(year: year, month: today.month, day: today.day))
            else { return false }
            let distance = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? .max
            return abs(distance) <= onThisDayToleranceDays
        }
        .sorted { $0.date! > $1.date! }
    }

    /// The hero banner: a memory from this date if there is one, otherwise a pick that changes daily.
    /// Landscape clips win when there are any, because a vertical video in a wide banner is mostly crop.
    static func heroKey(_ items: [ShelfInput], now: Date = .now, calendar: Calendar = .current) -> String? {
        let landscape = items.filter { !$0.isVertical }
        let pool = landscape.isEmpty ? items : landscape
        if let memory = onThisDay(pool, now: now, calendar: calendar).first { return memory.key }
        let candidates = pool.filter { $0.date != nil }.map(\.key).sorted()
        guard !candidates.isEmpty else { return pool.map(\.key).sorted().first }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return candidates[day % candidates.count]
    }
}
