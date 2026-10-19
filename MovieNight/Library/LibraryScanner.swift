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
    /// Every container on https://en.wikipedia.org/wiki/Video_file_format that can hold playable video,
    /// plus common extras (divx, xvid, mpe). Left out on purpose: .m4p/.f4p (DRM, no third-party
    /// player can decrypt them), .yuv (raw frames with no header, so size and format are unknown),
    /// .gif/.gifv/.mng (images and web animations) and .f4a/.f4b (audio only).
    static let videoExtensions: Set<String> = [
        // Apple / MPEG-4 family
        "mov", "qt", "mp4", "m4v", "3gp", "3g2",
        // Matroska / WebM / Ogg
        "mkv", "mk3d", "webm", "ogv", "ogg",
        // MPEG program and transport streams, DVD and camcorder
        "mpg", "mpeg", "mpe", "mpv", "mp2", "m2v", "vob", "ts", "mts", "m2ts",
        // Windows
        "avi", "divx", "xvid", "wmv", "asf",
        // Flash
        "flv", "f4v",
        // Professional and older formats
        "mxf", "rm", "rmvb", "viv", "nsv", "roq", "svi", "amv", "drc",
    ]

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .creationDateKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Synchronous on purpose: DirectoryEnumerator cannot be iterated from an async context.
    func scan(root: URL) throws -> [ScannedFile] {
        // Never report "no files" for a folder we can't reach: the caller would delete the library.
        _ = try root.checkResourceIsReachable()
        let rootPath = root.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.keys,
            // Hidden files are not skipped because evicted iCloud files can appear as ".Name.mov.icloud".
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: root])
        }

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
                fileSize: isPlaceholder ? Self.placeholderSize(url) : Int64(values?.fileSize ?? 0),
                createdAt: values?.creationDate,
                isLocal: isLocal
            ))
        }
        return results
    }

    /// An evicted iCloud file's ".Name.icloud" stub is a small plist that records the real size.
    /// 0 when it can't be read.
    static func placeholderSize(_ url: URL) -> Int64 {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let size = plist["NSURLFileSizeKey"] as? NSNumber
        else { return 0 }
        return size.int64Value
    }
}
