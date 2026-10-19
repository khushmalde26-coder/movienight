import Foundation

/// One video as the Library and Collections tabs see it. A value, so the logic is pure and tested.
struct BrowseEntry: Sendable, Hashable {
    var key: String
    var title: String
    var fileName: String
    var collection: String
    var sourceID: UUID?
    var sourceName: String
    var isFileSource: Bool
    var date: Date?
    var addedAt: Date
    var duration: Double?
    var progressFraction: Double
    var isFinished: Bool
    var kind: ContentKind = .homeVideo
    var show: String?
    var season: Int?
    var episode: Int?
    var franchise: String?
    var isUHD = false
    var lastPlayedAt: Date?
    // From TitleChek, films only.
    var genres: [String] = []
    var directors: [String] = []
    var tmdbCollection: String?
    var year: Int?
}

enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recorded, added, title, length
    var id: Self { self }
    var title: String {
        switch self {
        case .recorded: "Date Recorded"
        case .added: "Date Added"
        case .title: "Title"
        case .length: "Length"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unwatched, inProgress, watched
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All Videos"
        case .unwatched: "Unwatched"
        case .inProgress: "In Progress"
        case .watched: "Watched"
        }
    }
}

enum LibraryQuery {
    /// Keys in display order. Newest, longest or A–Z first unless `ascending` flips it.
    static func apply(_ entries: [BrowseEntry], sort: LibrarySort, ascending: Bool = false,
                      filter: LibraryFilter = .all, search: String = "", calendar: Calendar = .current) -> [String] {
        let words = search.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let matching = entries.filter { entry in
            switch filter {
            case .all: break
            case .unwatched: if entry.isFinished || entry.progressFraction > 0.02 { return false }
            case .inProgress: if entry.isFinished || entry.progressFraction <= 0.02 { return false }
            case .watched: if !entry.isFinished { return false }
            }
            guard !words.isEmpty else { return true }
            let haystack = searchableText(entry, calendar: calendar)
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        // Title order puts A first, so its natural direction is the opposite of the others.
        let sorted = matching.sorted { a, b in
            switch sort {
            case .recorded: return (a.date ?? .distantPast, a.key) > (b.date ?? .distantPast, b.key)
            case .added: return (a.addedAt, a.key) > (b.addedAt, b.key)
            case .length: return (a.duration ?? 0, a.key) > (b.duration ?? 0, b.key)
            case .title:
                let order = a.title.localizedStandardCompare(b.title)
                return order == .orderedSame ? a.key < b.key : order == .orderedAscending
            }
        }
        return (ascending ? sorted.reversed() : sorted).map(\.key)
    }

    /// Title, file name, folder, library, plus the year and month it was shot ("2019", "July").
    static func searchableText(_ entry: BrowseEntry, calendar: Calendar = .current) -> String {
        var parts = [entry.title, entry.fileName, entry.collection, entry.sourceName]
        if let date = entry.date {
            parts.append(String(calendar.component(.year, from: date)))
            parts.append(date.formatted(Date.FormatStyle(calendar: calendar).month(.wide)))
        }
        return parts.joined(separator: " ")
    }
}

/// A collection card: a top-level folder, the loose videos at a folder's root, or individually added videos.
struct CollectionGroup: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    /// Library name, shown when two folders in different libraries share a name.
    var detail: String?
    var itemKeys: [String]
    var coverKey: String?
    var years: ClosedRange<Int>?
}

enum CollectionBuilder {
    static let singleVideosID = "single-videos"

    static func build(_ entries: [BrowseEntry], calendar: Calendar = .current) -> [CollectionGroup] {
        let grouped = Dictionary(grouping: entries) { entry -> String in
            if entry.isFileSource { return singleVideosID }
            let source = entry.sourceID?.uuidString ?? "?"
            return entry.collection.isEmpty ? "\(source)/" : "\(source)/\(entry.collection)"
        }
        var groups = grouped.map { id, members -> CollectionGroup in
            let newestFirst = members.sorted { ($0.date ?? .distantPast, $0.key) > ($1.date ?? .distantPast, $1.key) }
            let first = members[0]
            let title: String
            if id == singleVideosID { title = "Individual Videos" }
            else if first.collection.isEmpty { title = first.sourceName }
            else { title = first.collection }
            let years = members.compactMap { $0.date.map { calendar.component(.year, from: $0) } }
            return CollectionGroup(
                id: id, title: title, detail: first.collection.isEmpty ? nil : first.sourceName,
                itemKeys: newestFirst.map(\.key), coverKey: newestFirst.first?.key,
                years: years.min().flatMap { low in years.max().map { low...$0 } }
            )
        }
        // The library name only helps when two cards would otherwise look the same.
        let titleCounts = Dictionary(grouping: groups, by: \.title).mapValues(\.count)
        for index in groups.indices where titleCounts[groups[index].title, default: 0] < 2 {
            groups[index].detail = nil
        }
        return groups.sorted { a, b in
            if (a.id == singleVideosID) != (b.id == singleVideosID) { return b.id == singleVideosID }
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    static func subtitle(_ group: CollectionGroup) -> String {
        var parts = ["\(group.itemKeys.count) video\(group.itemKeys.count == 1 ? "" : "s")"]
        if let years = group.years {
            parts.append(years.lowerBound == years.upperBound ? String(years.lowerBound) : "\(years.lowerBound)–\(years.upperBound)")
        }
        if let detail = group.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }
}
