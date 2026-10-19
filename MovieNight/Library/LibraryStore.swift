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
        // Needed on iOS before bookmarking a picker URL; harmless on macOS.
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try SecurityScopedBookmark.make(for: url)
            let source = LibrarySource(name: FileManager.default.displayName(atPath: url.path), bookmark: bookmark)
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
            guard FileManager.default.fileExists(atPath: url.path) else {
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
        scanningSources.insert(source.id)
        defer { scanningSources.remove(source.id) }

        let files: [ScannedFile]
        do {
            files = try await scanner.scan(root: root)
        } catch {
            lastError = "Couldn't read \(source.name): \(error.localizedDescription)"
            return
        }

        var existing = Dictionary(uniqueKeysWithValues: source.items.map { ($0.key, $0) })
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
            }
            if file.isLocal && item.isPlayable == nil {
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
        for (index, item) in items.enumerated() {
            await enrich(item, root: root)
            if index % 10 == 9 { try? context.save() }
        }
        try? context.save()
    }

    private func enrich(_ item: MediaItem, root: URL) async {
        let url = root.appending(path: item.relativePath)
        let key = item.key
        let metadata = await MetadataReader.read(url)
        item.duration = metadata.duration
        item.recordedAt = metadata.recordedAt
        item.isPlayable = metadata.isPlayable
        if metadata.isPlayable, item.thumbnailFile == nil {
            item.thumbnailFile = await ThumbnailService.generate(for: url, key: key, duration: metadata.duration)
        }
    }

    // MARK: Playback support

    func isAvailable(_ item: MediaItem) -> Bool {
        guard let id = item.source?.id else { return false }
        return !offlineSources.contains(id)
    }

    func fileURL(for item: MediaItem) -> URL? {
        guard let source = item.source, let root = activate(source) else { return nil }
        return root.appending(path: item.relativePath)
    }

    /// Downloads an evicted iCloud file and fills in metadata, so playback can start.
    func prepareForPlayback(_ item: MediaItem) async throws -> URL {
        guard let source = item.source, let root = activate(source) else {
            throw PlaybackError.sourceOffline
        }
        var url = root.appending(path: item.relativePath)
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            while true {
                url.removeAllCachedResourceValues()
                let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
                if status == .current { break }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        if item.isPlayable == nil {
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
        }
        try? context.save()
    }

    func setWatched(_ item: MediaItem, _ watched: Bool) {
        item.isFinished = watched
        item.progressSeconds = 0
        if !watched { item.lastPlayedAt = nil }
        try? context.save()
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
        case .unsupportedFormat: "This format needs the extended player, which isn't built yet."
        }
    }
}
