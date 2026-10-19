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
    // Set by ContentClassifier on every scan, from names and folders.
    var kindRaw: String?
    var cleanTitle: String?
    var showName: String?
    var season: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var releaseYear: Int?
    var franchise: String?
    /// MetadataReader.version that last read this file; lower means re-read on next scan.
    var metadataVersion: Int = 0

    // Watch state.
    var progressSeconds: Double = 0
    var lastPlayedAt: Date?
    var isFinished: Bool = false

    var source: LibrarySource?
    /// What TitleChek found on TMDB, shared with the other files of the same film or show.
    var info: TitleInfo?

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
    var kind: ContentKind {
        kindRaw.flatMap(ContentKind.init(rawValue:))
            ?? (DisplayTitle.isCameraName((fileName as NSString).deletingPathExtension) ? .homeVideo : .film)
    }

    /// Best guess at when a home video was shot. Films and episodes have none: their file dates are
    /// when they were copied, and encoders stamp their own "creation" dates.
    var bestDate: Date? { kind == .homeVideo ? recordedAt ?? fileCreatedAt : nil }

    /// What to sort and group by in time: the shooting date for home videos, the release year otherwise.
    var sortDate: Date? {
        if kind == .homeVideo { return bestDate }
        return year.flatMap { DateComponents(calendar: Calendar(identifier: .gregorian), year: $0, month: 1, day: 1).date }
    }

    /// "S4 E9" or "S4 E9 · The Wedding".
    var episodeLabel: String? {
        guard kind == .episode, let episodeNumber else { return nil }
        let number = "S\(season ?? 1) E\(episodeNumber)"
        return resolvedEpisodeTitle.map { "\(number) · \($0)" } ?? number
    }

    /// Release year: TMDB's when TitleChek matched it, else the one in the file name.
    var year: Int? { (kind == .film ? info?.year : nil) ?? releaseYear }

    /// The show's name as TMDB has it, else the folder's.
    var showTitle: String? { showName.map { info?.title ?? $0 } }

    /// From the file name, else from TMDB's episode list.
    var resolvedEpisodeTitle: String? {
        episodeTitle ?? episodeNumber.flatMap { info?.episodeName(season: season ?? 1, episode: $0) }
    }

    /// Artwork for cards: a matched film's TMDB backdrop, else the frame grabbed from the file.
    var artworkFile: String? {
        if kind == .film, let backdrop = info?.backdropFile { return backdrop }
        return thumbnailFile
    }

    /// For a show's card and banner: the show's TMDB backdrop, else this file's frame.
    var showArtworkFile: String? { info?.backdropFile ?? thumbnailFile }

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

    var displayTitle: String {
        switch kind {
        case .homeVideo: DisplayTitle.make(fileName: fileName, recordedAt: bestDate)
        case .episode: [showTitle, episodeNumber.map { "S\(season ?? 1) E\($0)" }].compactMap { $0 }.joined(separator: " ")
        case .film: info?.title ?? cleanTitle ?? DisplayTitle.clean((fileName as NSString).deletingPathExtension)
        case .extra: cleanTitle ?? DisplayTitle.clean((fileName as NSString).deletingPathExtension)
        }
    }

    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(progressSeconds / duration, 1)
    }

    var browseEntry: BrowseEntry {
        BrowseEntry(key: key, title: displayTitle, fileName: fileName, collection: collection, sourceID: source?.id,
                    sourceName: source?.name ?? "", isFileSource: source?.isFile ?? false, date: sortDate,
                    addedAt: addedAt, duration: duration, progressFraction: progressFraction, isFinished: isFinished,
                    kind: kind, show: showTitle, season: season, episode: episodeNumber, franchise: franchise,
                    isUHD: quality?.resolutionBadge == "4K", lastPlayedAt: lastPlayedAt,
                    genres: kind == .film ? info?.genres ?? [] : [], directors: kind == .film ? info?.directors ?? [] : [],
                    tmdbCollection: kind == .film ? info?.collectionName : nil, year: year)
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
