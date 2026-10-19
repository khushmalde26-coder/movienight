import Foundation
import SwiftData

/// One video file inside a `LibrarySource`. Paths are stored relative to the
/// source so a drive that mounts at a different path still matches.
@Model
final class MediaItem {
    /// "<source id>/<relative path>", stable across rescans.
    @Attribute(.unique) var key: String
    var relativePath: String
    /// Top-level folder inside the source, used for collection shelves. Empty for files at the root.
    var collection: String
    var fileName: String
    var fileSize: Int64
    var fileCreatedAt: Date?
    var addedAt: Date

    // Filled in by MetadataReader / MPVProbe once the bytes are local.
    var recordedAt: Date?
    var duration: Double?
    /// nil until checked. false means neither engine could open it (damaged, DRM, not really video).
    var isPlayable: Bool?
    /// Which engine plays it. See PlaybackEngine.
    var engineRaw: String?
    var thumbnailFile: String?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var videoCodec: String?
    var isHDR: Bool = false
    var audioChannels: Int?
    /// JSON-encoded [Chapter]; nil when the file has none.
    var chaptersData: Data?
    /// false for an iCloud file that isn't downloaded. Updated on every scan.
    var isLocal: Bool = true
    /// MetadataReader.version that last read this file; lower means re-read on next scan.
    var metadataVersion: Int = 0

    // Watch state.
    var progressSeconds: Double = 0
    var lastPlayedAt: Date?
    var isFinished: Bool = false

    var source: LibrarySource?

    init(key: String, relativePath: String, collection: String, fileName: String, fileSize: Int64, fileCreatedAt: Date?) {
        self.key = key
        self.relativePath = relativePath
        self.collection = collection
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileCreatedAt = fileCreatedAt
        self.addedAt = .now
    }

    /// Best guess at when the clip was shot.
    var bestDate: Date? { recordedAt ?? fileCreatedAt }

    var engine: PlaybackEngine? {
        get { engineRaw.flatMap(PlaybackEngine.init(rawValue:)) }
        set { engineRaw = newValue?.rawValue }
    }

    var quality: VideoQuality? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return VideoQuality(width: width, height: height, frameRate: frameRate, isHDR: isHDR,
                            isDolbyVision: videoCodec == "Dolby Vision")
    }

    var needsMetadata: Bool { metadataVersion < MetadataReader.version }

    var chapters: [Chapter] {
        get { chaptersData.flatMap { try? JSONDecoder().decode([Chapter].self, from: $0) } ?? [] }
        set { chaptersData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Where playback starts: the saved position, or nil to start from the beginning.
    func resumePosition(startFromBeginning: Bool = PlaybackPreferences.startFromBeginning) -> Double? {
        guard !startFromBeginning, !isFinished, progressSeconds > 5 else { return nil }
        return progressSeconds
    }

    /// Shown in the Continue Watching row: started, not finished, and not dismissed from the row.
    var isInContinueWatching: Bool {
        !isFinished && progressFraction > 0.02 && lastPlayedAt != nil
    }

    var remainingSeconds: Double? {
        guard let duration, progressSeconds > 0, !isFinished else { return nil }
        return max(duration - progressSeconds, 0)
    }

    var displayTitle: String { DisplayTitle.make(fileName: fileName, recordedAt: bestDate) }

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(progressSeconds / duration, 1)
    }

    var browseEntry: BrowseEntry {
        BrowseEntry(key: key, title: displayTitle, fileName: fileName, collection: collection, sourceID: source?.id,
                    sourceName: source?.name ?? "", isFileSource: source?.isFile ?? false, date: bestDate,
                    addedAt: addedAt, duration: duration, progressFraction: progressFraction, isFinished: isFinished)
    }

    var healthInput: HealthInput {
        HealthInput(key: key, fileName: fileName, fileSize: fileSize, duration: duration, isPlayable: isPlayable, isLocal: isLocal)
    }

    var snapshot: ShelfInput {
        ShelfInput(
            key: key,
            collection: collection,
            date: bestDate,
            addedAt: addedAt,
            progressFraction: progressFraction,
            duration: duration,
            isVertical: quality?.isVertical ?? false,
            lastPlayedAt: lastPlayedAt,
            isFinished: isFinished
        )
    }
}
