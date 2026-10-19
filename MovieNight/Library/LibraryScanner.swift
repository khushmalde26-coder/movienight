import Foundation

struct ScannedFile: Sendable {
    var relativePath: String
    var collection: String
    var fileName: String
    var fileSize: Int64
    var createdAt: Date?
    /// false for iCloud files that have been evicted to save space.
    var isLocal: Bool
}

/// Walks a source folder off the main thread. Reads only file-system metadata, never file contents,
/// so it is cheap on evicted iCloud files and slow drives.
actor LibraryScanner {
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mkv", "avi", "webm", "mts", "m2ts", "3gp", "wmv", "mpg", "mpeg", "ts",
    ]

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .creationDateKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Synchronous on purpose: DirectoryEnumerator cannot be iterated from an async context.
    func scan(root: URL) throws -> [ScannedFile] {
        let rootPath = root.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.keys,
            // Hidden files are not skipped because evicted iCloud files can appear as ".Name.mov.icloud".
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [ScannedFile] = []
        while let url = enumerator.nextObject() as? URL {
            var name = url.lastPathComponent
            var isPlaceholder = false
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                isPlaceholder = true
            } else if name.hasPrefix(".") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard Self.videoExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(Self.keys))
            guard isPlaceholder || values?.isRegularFile == true else { continue }

            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
            let relativeDir = parent.hasPrefix(rootPath) ? String(parent.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : ""
            let relativePath = relativeDir.isEmpty ? name : relativeDir + "/" + name

            let isLocal: Bool
            if isPlaceholder {
                isLocal = false
            } else if values?.isUbiquitousItem == true {
                isLocal = values?.ubiquitousItemDownloadingStatus == .current
            } else {
                isLocal = true
            }

            results.append(ScannedFile(
                relativePath: relativePath,
                collection: relativeDir.split(separator: "/").first.map(String.init) ?? "",
                fileName: name,
                fileSize: Int64(values?.fileSize ?? 0),
                createdAt: values?.creationDate,
                isLocal: isLocal
            ))
        }
        return results
    }
}
