import Foundation
import Testing
@testable import MovieNight

struct LibraryQueryTests {
    private let library = UUID(), drive = UUID()
    private func entry(_ key: String, title: String, collection: String = "", source: UUID? = nil, sourceName: String = "Videos",
                       file: Bool = false, year: Int? = nil, added: TimeInterval = 0, length: Double? = nil,
                       progress: Double = 0, finished: Bool = false) -> BrowseEntry {
        BrowseEntry(key: key, title: title, fileName: key, collection: collection, sourceID: source ?? library, sourceName: sourceName,
                    isFileSource: file, date: year.map { DateComponents(calendar: .init(identifier: .gregorian), year: $0, month: 7, day: 14).date! },
                    addedAt: Date(timeIntervalSince1970: added), duration: length, progressFraction: progress, isFinished: finished)
    }

    private var sample: [BrowseEntry] {
        [
            entry("a", title: "Beach day", collection: "Holidays", year: 2019, added: 3, length: 60),
            entry("b", title: "Wedding", year: 2018, added: 1, length: 3600, finished: true),
            entry("c", title: "Ålesund trip", collection: "Holidays", year: 2022, added: 2, length: 600, progress: 0.4),
            entry("d", title: "Undated clip", added: 4, length: nil),
        ]
    }

    @Test func sortsEachWay() {
        #expect(LibraryQuery.apply(sample, sort: .recorded) == ["c", "a", "b", "d"])        // undated last
        #expect(LibraryQuery.apply(sample, sort: .recorded, ascending: true) == ["d", "b", "a", "c"])
        #expect(LibraryQuery.apply(sample, sort: .added) == ["d", "a", "c", "b"])
        #expect(LibraryQuery.apply(sample, sort: .length) == ["b", "c", "a", "d"])
        #expect(LibraryQuery.apply(sample, sort: .title) == ["c", "a", "d", "b"].sorted { k1, k2 in
            let titles = ["a": "Beach day", "b": "Wedding", "c": "Ålesund trip", "d": "Undated clip"]
            return titles[k1]!.localizedStandardCompare(titles[k2]!) == .orderedAscending
        })
    }

    @Test func filtersByWatchState() {
        #expect(LibraryQuery.apply(sample, sort: .added, filter: .unwatched) == ["d", "a"])
        #expect(LibraryQuery.apply(sample, sort: .added, filter: .inProgress) == ["c"])
        #expect(LibraryQuery.apply(sample, sort: .added, filter: .watched) == ["b"])
    }

    @Test func searchesTitlesFoldersAndYearsWithoutCaringAboutAccents() {
        #expect(Set(LibraryQuery.apply(sample, sort: .added, search: "holidays")) == ["a", "c"])
        #expect(LibraryQuery.apply(sample, sort: .added, search: "alesund") == ["c"])
        #expect(LibraryQuery.apply(sample, sort: .added, search: "2018") == ["b"])
        #expect(LibraryQuery.apply(sample, sort: .added, search: "beach 2019") == ["a"])     // every word must match
        #expect(LibraryQuery.apply(sample, sort: .added, search: "beach 2020").isEmpty)
    }

    @Test func groupsFoldersRootsAndSingleVideos() {
        let entries = [
            entry("1", title: "One", collection: "Holidays", year: 2019),
            entry("2", title: "Two", collection: "Holidays", year: 2021),
            entry("3", title: "Loose", year: 2020),
            entry("4", title: "Other drive", collection: "Holidays", source: drive, sourceName: "SSD", year: 2015),
            entry("5", title: "Picked", source: UUID(), sourceName: "Picked.mp4", file: true),
        ]
        let groups = CollectionBuilder.build(entries)
        #expect(groups.map(\.title) == ["Holidays", "Holidays", "Videos", "Individual Videos"])
        let local = groups.first { $0.itemKeys.contains("1") }!
        #expect(local.itemKeys == ["2", "1"])                // newest first
        #expect(local.coverKey == "2")
        #expect(CollectionBuilder.subtitle(local) == "2 videos · 2019–2021 · Videos")   // same name twice: library shown
        #expect(groups.last?.id == CollectionBuilder.singleVideosID)
        let loose = groups.first { $0.title == "Videos" }!
        #expect(loose.detail == nil)
        #expect(CollectionBuilder.subtitle(loose) == "1 video · 2020")
    }
}

struct HomeShelvesTests {
    private func shelf(_ kind: Shelf.Kind) -> Shelf { Shelf(kind: kind, title: "\(kind)", itemKeys: ["x"]) }

    @Test func keepsTheEssentialsAndAFewHighlights() {
        let all = [
            shelf(.continueWatching), shelf(.onThisDay), shelf(.recentlyAdded), shelf(.longVideos),
            shelf(.collection("A")), shelf(.collection("B")), shelf(.year(2024)), shelf(.year(2023)),
            shelf(.quickClips), shelf(.undated),
        ]
        #expect(ShelfBuilder.homeShelves(all).map(\.kind) == [
            .continueWatching, .onThisDay, .recentlyAdded, .longVideos, .year(2024), .quickClips,
        ])
        #expect(ShelfBuilder.homeShelves([shelf(.year(2020)), shelf(.collection("A")), shelf(.undated)]).map(\.kind) == [
            .year(2020), .collection("A"),
        ])
    }
}
