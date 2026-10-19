import Foundation
import SwiftData
import Testing
@testable import MovieNight

struct WatchHistoryTests {
    private let mb: Int64 = 1_000_000
    private let old = Date(timeIntervalSince1970: 1_000)
    private let new = Date(timeIntervalSince1970: 2_000)

    @Test func sameNameDifferentRealSizeIsADifferentVideo() {
        // Two phones' IMG_0001.MOV: both sizes are real and differ.
        #expect(WatchHistory.bestMatch(fileSize: 50 * mb, in: [.init(fileSize: 80 * mb, savedAt: old)]) == nil)
    }

    @Test func sameSizeWinsThenNewest() {
        let candidates: [WatchHistory.Candidate] = [
            .init(fileSize: 200, savedAt: new),      // iCloud placeholder size, can't compare
            .init(fileSize: 50 * mb, savedAt: old),  // exact size
        ]
        #expect(WatchHistory.bestMatch(fileSize: 50 * mb, in: candidates) == 1)
        #expect(WatchHistory.bestMatch(fileSize: 300, in: candidates) == 0)
    }

    @Test func noCandidatesNoMatch() {
        #expect(WatchHistory.bestMatch(fileSize: 50 * mb, in: []) == nil)
    }

    @Test func resumeRespectsStartFromBeginning() {
        let item = MediaItem(key: "k", relativePath: "a.mp4", collection: "", fileName: "a.mp4", fileSize: 1, fileCreatedAt: nil)
        item.progressSeconds = 120
        #expect(item.resumePosition(startFromBeginning: false) == 120)
        #expect(item.resumePosition(startFromBeginning: true) == nil)
        item.isFinished = true
        #expect(item.resumePosition(startFromBeginning: false) == nil)
    }

    /// Moving a file to another folder keeps its watch state; renaming it starts fresh.
    @MainActor
    @Test func movedFileKeepsHistoryRenamedFileDoesNot() async throws {
        let root = URL.temporaryDirectory.appending(path: "HistoryTest-\(UUID().uuidString)")
        let first = root.appending(path: "Trip/clip.mp4")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: first)
        defer { try? FileManager.default.removeItem(at: root) }

        let container = try ModelContainer(
            for: LibrarySource.self, MediaItem.self, WatchRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = LibraryStore(context: container.mainContext)
        let source = LibrarySource(name: "Test", bookmark: try SecurityScopedBookmark.make(for: root))
        container.mainContext.insert(source)

        await store.rescan(source)
        let item = try #require(source.items.first)
        store.saveProgress(item, seconds: 42)

        let moved = root.appending(path: "Archive/clip.mp4")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: first, to: moved)
        await store.rescan(source)
        #expect(source.items.map(\.relativePath) == ["Archive/clip.mp4"])
        #expect(source.items.first?.progressSeconds == 42)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WatchRecord>()) == 0)

        try FileManager.default.moveItem(at: moved, to: root.appending(path: "Archive/renamed.mp4"))
        await store.rescan(source)
        #expect(source.items.map(\.relativePath) == ["Archive/renamed.mp4"])
        #expect(source.items.first?.progressSeconds == 0)
    }
}
