import Foundation
import Testing
@testable import MovieNight

struct ShelfBuilderTests {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string + "T12:00:00Z")!
    }

    private func item(_ key: String, date: String?, collection: String = "", added: String = "2026-01-01",
                      progress: Double = 0, played: String? = nil, finished: Bool = false) -> ShelfInput {
        ShelfInput(key: key, collection: collection, date: date.map(day), addedAt: day(added),
                   progressFraction: progress, lastPlayedAt: played.map(day), isFinished: finished)
    }

    @Test func groupsByYearNewestFirst() {
        let shelves = ShelfBuilder.build([
            item("a", date: "2019-03-01"), item("b", date: "2021-05-01"), item("c", date: "2019-08-01"),
        ], now: day("2026-10-19"), calendar: calendar)
        let years = shelves.filter { if case .year = $0.kind { true } else { false } }
        #expect(years.map(\.title) == ["2021", "2019"])
        #expect(years.last?.itemKeys == ["c", "a"])
    }

    @Test func continueWatchingSkipsFinishedAndUntouched() {
        let shelves = ShelfBuilder.build([
            item("half", date: nil, progress: 0.5, played: "2026-10-18"),
            item("done", date: nil, progress: 0.5, played: "2026-10-18", finished: true),
            item("fresh", date: nil),
        ], now: day("2026-10-19"), calendar: calendar)
        #expect(shelves.first?.kind == .continueWatching)
        #expect(shelves.first?.itemKeys == ["half"])
    }

    @Test func onThisDayUsesEarlierYearsWithinTolerance() {
        let items = [
            item("hit", date: "2018-10-17"),
            item("miss", date: "2018-11-19"),
            item("thisYear", date: "2026-10-19"),
        ]
        let memories = ShelfBuilder.onThisDay(items, now: day("2026-10-19"), calendar: calendar)
        #expect(memories.map(\.key) == ["hit"])
        #expect(ShelfBuilder.heroKey(items, now: day("2026-10-19"), calendar: calendar) == "hit")
    }

    @Test func recentlyAddedHiddenOnFirstImport() {
        let shelves = ShelfBuilder.build([
            item("a", date: nil, added: "2026-10-18"), item("b", date: nil, added: "2026-10-18"),
        ], now: day("2026-10-19"), calendar: calendar)
        #expect(!shelves.contains { $0.kind == .recentlyAdded })
    }

    @Test func folderHoldingEverythingIsNotAShelf() {
        let shelves = ShelfBuilder.build([
            item("a", date: nil, collection: "Holidays"), item("b", date: nil, collection: "Holidays"),
        ], now: day("2026-10-19"), calendar: calendar)
        #expect(!shelves.contains { $0.kind == .collection("Holidays") })
    }
}
