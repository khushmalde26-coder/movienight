import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import MovieNight

struct ScrubThumbnailerTests {
    private func video() async throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "Scrub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "Clip.mp4")
        try await AppleEngineTests.makeVideo(at: url)
        return url
    }

    @Test func appleThumbnailerGivesASmallFrame() async throws {
        let url = try await video()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let thumbnailer = AssetScrubThumbnailer(asset: AVURLAsset(url: url))
        defer { thumbnailer.close() }
        let image = try #require(await thumbnailer.frame(at: 1.5))
        #expect(image.width <= 400 && image.width > 0)
    }

    /// The MKV path: a hidden mpv, scaled down by FFmpeg, answering repeated seeks.
    @Test func mpvThumbnailerGivesScaledFramesForEachSeek() async throws {
        let url = try await video()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let thumbnailer = MPVScrubThumbnailer(url: url)
        defer { thumbnailer.close() }
        for seconds in [0.5, 2.0, 1.0] {
            let image = try #require(await thumbnailer.frame(at: seconds))
            #expect(image.width == 320)
        }
    }
}

@MainActor
struct ContinueWatchingTests {
    @Test func removingStartsTheVideoOverNextTime() throws {
        let container = try ModelContainer(for: LibrarySource.self, MediaItem.self, WatchRecord.self, SavedMoment.self, TitleInfo.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: container.mainContext)
        let item = MediaItem(key: "k", relativePath: "a.mp4", collection: "", fileName: "a.mp4", fileSize: 1, fileCreatedAt: nil)
        item.duration = 600
        container.mainContext.insert(item)
        store.saveProgress(item, seconds: 120)
        #expect(item.isInContinueWatching)

        store.removeFromContinueWatching(item)
        #expect(!item.isInContinueWatching)
        #expect(item.resumePosition(startFromBeginning: false) == nil)   // plays from the beginning
        #expect(!item.isFinished)

        store.saveProgress(item, seconds: 130)          // watching again brings it back
        #expect(item.isInContinueWatching)
    }

    @Test func startupAnimationShipsInTheApp() {
        #expect(Bundle(for: LibraryStore.self).url(forResource: "Startup", withExtension: "mp4") != nil
                || Bundle.main.url(forResource: "Startup", withExtension: "mp4") != nil)
    }
}
