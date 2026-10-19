import Testing
@testable import MovieNight

struct WatchHistoryTests {
    private struct Record: Equatable {
        let name: String
        let size: Int64
    }

    private func index(_ records: [Record]) -> WatchHistory.Index<Record> {
        WatchHistory.Index(records, fileName: { $0.name }, fileSize: { $0.size })
    }

    @Test func sameNameAndSizeMatchesWhateverTheFolder() {
        let history = index([Record(name: "Wedding.mp4", size: 900)])
        #expect(history.match(fileName: "Wedding.mp4", fileSize: 900) == Record(name: "Wedding.mp4", size: 900))
        #expect(history.match(fileName: "wedding.MP4", fileSize: 900) != nil)
    }

    @Test func renamedOrDifferentFileStartsFresh() {
        let history = index([Record(name: "Wedding.mp4", size: 900)])
        #expect(history.match(fileName: "Wedding 2019.mp4", fileSize: 900) == nil)
        // Another phone's IMG_0001.MOV is a different clip.
        #expect(history.match(fileName: "Wedding.mp4", fileSize: 901) == nil)
    }

    @Test func unknownSizeFallsBackToAUniqueName() {
        let history = index([
            Record(name: "Wedding.mp4", size: 900),
            Record(name: "IMG_0001.MOV", size: 10), Record(name: "IMG_0001.MOV", size: 20),
        ])
        #expect(history.match(fileName: "Wedding.mp4", fileSize: 0) != nil)
        #expect(history.match(fileName: "IMG_0001.MOV", fileSize: 0) == nil)
    }
}
