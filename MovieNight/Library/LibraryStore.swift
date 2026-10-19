import Foundation
import Observation
import SwiftData

/// Owns folder access, scanning and enrichment. Views read items through @Query;
/// this type only writes.
@MainActor
@Observable
final class LibraryStore {
    private let context: ModelContext
    private let scanner = LibraryScanner()

    /// Resolved root folders we currently hold security-scoped access to.
    private var roots: [UUID: URL] = [:]
    private(set) var offlineSources: Set<UUID> = []
    private(set) var scanningSources: Set<UUID> = []
    var lastError: String?

    init(context: ModelContext) {
        self.context = context
    }

    var isScanning: Bool { !scanningSources.isEmpty }

    // MARK: Sources

    func addFolder(_ url: URL) async {
        await add(url, isFile: false)
    }

    /// Individual videos. Each becomes its own source with its own bookmark, so it has the same
    /// offline behaviour as a folder: kept, greyed out, while its drive is away.
    func addFiles(_ urls: [URL]) async {
        let alreadyAdded = Set(fileSourcePaths())
        for url in urls {
            guard LibraryScanner.videoExtensions.contains(url.pathExtension.lowercased()) else {
                lastError = "\(url.lastPathComponent) isn't a video file."
                continue
            }
            guard !alreadyAdded.contains(url.standardizedFileURL.path) else { continue }
            await add(url, isFile: true)
        }
    }

    private func fileSourcePaths() -> [String] {
        let sources = (try? context.fetch(FetchDescriptor<LibrarySource>(predicate: #Predicate { $0.isFile == true }))) ?? []
        return sources.compactMap { source in
            (roots[source.id] ?? (try? SecurityScopedBookmark.resolve(source.bookmark))?.url)?.standardizedFileURL.path
        }
    }

    private func add(_ url: URL, isFile: Bool) async {
        // Needed on iOS before bookmarking a picker URL; harmless on macOS.
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try SecurityScopedBookmark.make(for: url)
            let source = LibrarySource(name: FileManager.default.displayName(atPath: url.path), bookmark: bookmark,
                                       isFile: isFile)
            context.insert(source)
            try context.save()
            if didStart { url.stopAccessingSecurityScopedResource() }
            activate(source)
            await rescan(source)
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            lastError = "Couldn't add \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func remove(_ source: LibrarySource) {
        roots.removeValue(forKey: source.id)?.stopAccessingSecurityScopedResource()
        offlineSources.remove(source.id)
        for item in source.items {
            archiveHistory(of: item)
            if let thumb = item.thumbnailFile {
                try? FileManager.default.removeItem(at: ThumbnailService.directory.appending(path: thumb))
            }
        }
        context.delete(source)
        try? context.save()
    }

    func activateAll() {
        let sources = (try? context.fetch(FetchDescriptor<LibrarySource>())) ?? []
        for source in sources { activate(source) }
    }

    /// Resolves the bookmark and starts access. An unplugged drive or signed-out iCloud
    /// marks the source offline but keeps its items, so the library survives the drive coming back.
    @discardableResult
    func activate(_ source: LibrarySource) -> URL? {
        if let url = roots[source.id] { return url }
        do {
            let (url, isStale) = try SecurityScopedBookmark.resolve(source.bookmark)
            _ = url.startAccessingSecurityScopedResource()
            guard isReachable(source, at: url) else {
                url.stopAccessingSecurityScopedResource()
                offlineSources.insert(source.id)
                return nil
            }
            if isStale, let fresh = try? SecurityScopedBookmark.make(for: url) {
                source.bookmark = fresh
            }
            roots[source.id] = url
            offlineSources.remove(source.id)
            return url
        } catch {
            offlineSources.insert(source.id)
            return nil
        }
    }

    // MARK: Scanning

    func rescanAll() async {
        let sources = (try? context.fetch(FetchDescriptor<LibrarySource>())) ?? []
        for source in sources {
            await rescan(source)
        }
    }

    func rescan(_ source: LibrarySource) async {
        guard let root = activate(source), !scanningSources.contains(source.id) else { return }
        // A drive unplugged since launch still has a cached root. Scanning it would find nothing and
        // delete every item, so confirm it's really there first.
        guard isReachable(source, at: root) else {
            markOffline(source)
            return
        }
        scanningSources.insert(source.id)
        defer { scanningSources.remove(source.id) }

        let files: [ScannedFile]
        do {
            files = source.isFile ? [try await scanner.scan(file: root)] : try await scanner.scan(root: root)
        } catch {
            if !isReachable(source, at: root) { markOffline(source) }
            lastError = "Couldn't read \(source.name): \(error.localizedDescription)"
            return
        }
        // The source may have been removed while the scan ran.
        guard !source.isDeleted else { return }

        var existing = Dictionary(uniqueKeysWithValues: source.items.map { ($0.key, $0) })
        // Keep the watch state of files that went away first, so a file that moved within this
        // folder gets it back below when it shows up at its new path.
        let foundKeys = Set(files.map { Self.key(source: source, relativePath: $0.relativePath) })
        for (key, item) in existing where !foundKeys.contains(key) {
            archiveHistory(of: item)
        }
        try? context.save()
        var toEnrich: [MediaItem] = []
        for file in files {
            let key = Self.key(source: source, relativePath: file.relativePath)
            let item: MediaItem
            if let found = existing.removeValue(forKey: key) {
                item = found
                item.fileSize = file.fileSize
                item.collection = file.collection
            } else {
                item = MediaItem(key: key, relativePath: file.relativePath, collection: file.collection,
                                 fileName: file.fileName, fileSize: file.fileSize, fileCreatedAt: file.createdAt)
                item.source = source
                context.insert(item)
                restoreHistory(of: item)
            }
            if let thumbnail = item.thumbnailFile, !ThumbnailService.exists(thumbnail) {
                item.thumbnailFile = nil
                item.metadataVersion = 0
            }
            if file.isLocal && item.needsMetadata {
                toEnrich.append(item)
            }
        }
        // Whatever is left was deleted or moved on disk. Safe because we know the source is online.
        for gone in existing.values {
            context.delete(gone)
        }
        source.lastScannedAt = .now
        try? context.save()

        await enrich(toEnrich, root: root)
    }

    /// Reads duration, embedded date and playability, then makes artwork. Saves in batches so
    /// shelves fill in progressively on a large first import.
    private func enrich(_ items: [MediaItem], root: URL) async {
        for (index, item) in items.enumerated() where !item.isDeleted {
            await enrich(item, root: root)
            if index % 10 == 9 { try? context.save() }
        }
        try? context.save()
    }

    /// AVFoundation first (fast, and it means AVKit can play it); anything it can't open goes
    /// through mpv/FFmpeg, which handles MKV, AVI, WMV, FLV, RealMedia, VOB and the rest.
    private func enrich(_ item: MediaItem, root: URL) async {
        let url = Self.url(of: item, root: root)
        let key = item.key
        var metadata = await MetadataReader.read(url)
        var thumbnail: String?

        if metadata.isPlayable, metadata.width != nil {
            item.engine = .avKit
            if item.thumbnailFile == nil {
                thumbnail = await ThumbnailService.generate(for: url, key: key, duration: metadata.duration)
            }
        } else {
            let frameDirectory = URL.temporaryDirectory.appending(path: "Probe-\(UUID().uuidString)")
            let probe = await MPVProbe.probe(url, frameDirectory: frameDirectory)
            metadata = probe.metadata
            item.engine = metadata.isPlayable ? .mpv : nil
            if item.thumbnailFile == nil, let frame = probe.frameFile {
                thumbnail = ThumbnailService.store(frameAt: frame, key: key)
            }
            try? FileManager.default.removeItem(at: frameDirectory)
        }
        // Reading can take seconds; the item or its folder may have been removed meanwhile.
        guard !item.isDeleted else { return }

        item.duration = metadata.duration
        item.recordedAt = metadata.recordedAt
        item.isPlayable = metadata.isPlayable
        item.width = metadata.width
        item.height = metadata.height
        item.frameRate = metadata.frameRate
        item.videoCodec = metadata.videoCodec
        item.isHDR = metadata.isHDR
        item.audioChannels = metadata.audioChannels
        item.metadataVersion = MetadataReader.version
        if let thumbnail { item.thumbnailFile = thumbnail }
    }

    // MARK: Playback support

    /// Called when drives mount or unmount (macOS) and when the app returns to the foreground:
    /// drops roots that disappeared, picks up sources that came back, and scans those.
    func refreshAvailability() async {
        let sources = (try? context.fetch(FetchDescriptor<LibrarySource>())) ?? []
        for source in sources {
            if let root = roots[source.id], !isReachable(source, at: root) {
                markOffline(source)
            } else if offlineSources.contains(source.id), activate(source) != nil {
                await rescan(source)
            }
        }
    }

    /// A file source also counts as there when iCloud has evicted it and left a placeholder.
    private func isReachable(_ source: LibrarySource, at url: URL) -> Bool {
        LibraryScanner.isReachable(url) || (source.isFile && LibraryScanner.isReachable(LibraryScanner.placeholder(for: url)))
    }

    /// A file source's root is the video itself; a folder's items sit below it.
    static func url(of item: MediaItem, root: URL) -> URL {
        item.source?.isFile == true ? root : root.appending(path: item.relativePath)
    }

    private func markOffline(_ source: LibrarySource) {
        roots.removeValue(forKey: source.id)?.stopAccessingSecurityScopedResource()
        offlineSources.insert(source.id)
    }

    func isAvailable(_ item: MediaItem) -> Bool {
        guard let id = item.source?.id else { return false }
        return !offlineSources.contains(id)
    }

    func fileURL(for item: MediaItem) -> URL? {
        guard let source = item.source, let root = activate(source) else { return nil }
        return Self.url(of: item, root: root)
    }

    /// Downloads an evicted iCloud file and fills in metadata, so playback can start.
    func prepareForPlayback(_ item: MediaItem) async throws -> URL {
        guard let source = item.source, let root = activate(source) else {
            throw PlaybackError.sourceOffline
        }
        var url = Self.url(of: item, root: root)
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            // Ends when the file is local, on a reported download error, or when the player is closed
            // (Task.sleep throws on cancellation).
            while true {
                url.removeAllCachedResourceValues()
                let values = try url.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey,
                ])
                if values.ubiquitousItemDownloadingStatus == .current { break }
                if let error = values.ubiquitousItemDownloadingError { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        if item.needsMetadata {
            await enrich(item, root: root)
            try? context.save()
        }
        return url
    }

    func saveProgress(_ item: MediaItem, seconds: Double) {
        item.progressSeconds = seconds
        item.lastPlayedAt = .now
        if let duration = item.duration, duration > 0, seconds / duration > 0.95 {
            item.isFinished = true
            item.progressSeconds = 0
        } else if seconds > 5 {
            // Rewatching a finished video: it's in progress again, so it can resume.
            item.isFinished = false
        }
        try? context.save()
    }

    func setWatched(_ item: MediaItem, _ watched: Bool) {
        item.isFinished = watched
        item.progressSeconds = 0
        if !watched { item.lastPlayedAt = nil }
        try? context.save()
    }

    // MARK: Watch history across moves

    private func archiveHistory(of item: MediaItem) {
        guard WatchHistory.hasHistory(progressSeconds: item.progressSeconds, lastPlayedAt: item.lastPlayedAt,
                                      isFinished: item.isFinished) else { return }
        context.insert(WatchRecord(from: item))
    }

    /// A new file whose name matches one that left the library takes over its watch state.
    private func restoreHistory(of item: MediaItem) {
        let name = WatchHistory.nameKey(item.fileName)
        let descriptor = FetchDescriptor<WatchRecord>(predicate: #Predicate { $0.nameKey == name })
        guard let records = try? context.fetch(descriptor), !records.isEmpty,
              let index = WatchHistory.bestMatch(
                  fileSize: item.fileSize,
                  in: records.map { .init(fileSize: $0.fileSize, savedAt: $0.savedAt) })
        else { return }
        let record = records[index]
        item.progressSeconds = record.progressSeconds
        item.lastPlayedAt = record.lastPlayedAt
        item.isFinished = record.isFinished
        context.delete(record)
    }

    static func key(source: LibrarySource, relativePath: String) -> String {
        source.id.uuidString + "/" + relativePath
    }
}

enum PlaybackError: LocalizedError {
    case sourceOffline
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .sourceOffline: "The drive or folder this video lives on isn't connected."
        case .unsupportedFormat: "This file couldn't be opened. It may be damaged, copy-protected, or not actually a video."
        }
    }
}
