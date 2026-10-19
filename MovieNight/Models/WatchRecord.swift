import Foundation
import SwiftData

/// Watch state kept for a video that left the library (moved, its folder removed, or deleted),
/// so it comes back when a file with the same name reappears. A renamed file starts fresh.
@Model
final class WatchRecord {
    /// Lowercased file name, the match key.
    var nameKey: String
    var fileSize: Int64
    var progressSeconds: Double
    var lastPlayedAt: Date?
    var isFinished: Bool
    var savedAt: Date

    init(from item: MediaItem) {
        nameKey = WatchHistory.nameKey(item.fileName)
        fileSize = item.fileSize
        progressSeconds = item.progressSeconds
        lastPlayedAt = item.lastPlayedAt
        isFinished = item.isFinished
        savedAt = .now
    }
}

/// Matching rules, kept pure so they're unit tested.
enum WatchHistory {
    /// Below this a size is an iCloud placeholder or otherwise not the real file size.
    static let reliableSize: Int64 = 1_000_000

    struct Candidate: Equatable {
        var fileSize: Int64
        var savedAt: Date
    }

    static func nameKey(_ fileName: String) -> String { fileName.lowercased() }

    static func hasHistory(progressSeconds: Double, lastPlayedAt: Date?, isFinished: Bool) -> Bool {
        isFinished || progressSeconds > 0 || lastPlayedAt != nil
    }

    /// Index of the record to restore for a file with this name, or nil.
    /// Camera names repeat (every phone has an IMG_0001.MOV), so when both sizes are real they must
    /// match; moving a file never changes its size. The same size wins over a size we can't trust.
    static func bestMatch(fileSize: Int64, in candidates: [Candidate]) -> Int? {
        let sizeKnown = fileSize >= reliableSize
        let usable = candidates.indices.filter { index in
            let other = candidates[index].fileSize
            return !(sizeKnown && other >= reliableSize && other != fileSize)
        }
        return usable.max { a, b in
            let aSame = candidates[a].fileSize == fileSize, bSame = candidates[b].fileSize == fileSize
            if aSame != bSame { return bSame }
            return candidates[a].savedAt < candidates[b].savedAt
        }
    }
}
