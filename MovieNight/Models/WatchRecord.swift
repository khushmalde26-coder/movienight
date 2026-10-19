import Foundation
import SwiftData

/// Watch state keyed by file name and size instead of path, so it survives a file moving to
/// another folder or drive, or a folder being removed and added back. A renamed file starts fresh.
@Model
final class WatchRecord {
    /// WatchHistory.fingerprint(fileName:fileSize:)
    @Attribute(.unique) var fingerprint: String
    var fileName: String
    var fileSize: Int64
    var progressSeconds: Double = 0
    var lastPlayedAt: Date?
    var isFinished: Bool = false

    init(fileName: String, fileSize: Int64) {
        self.fingerprint = WatchHistory.fingerprint(fileName: fileName, fileSize: fileSize)
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

enum WatchHistory {
    static func fingerprint(fileName: String, fileSize: Int64) -> String {
        fileName.lowercased() + "|" + String(fileSize)
    }

    /// Finds earlier watch state for a newly found file.
    struct Index<Record> {
        private var byFingerprint: [String: Record] = [:]
        private var byName: [String: [Record]] = [:]

        init(_ records: [Record], fileName: (Record) -> String, fileSize: (Record) -> Int64) {
            for record in records {
                byFingerprint[WatchHistory.fingerprint(fileName: fileName(record), fileSize: fileSize(record))] = record
                byName[fileName(record).lowercased(), default: []].append(record)
            }
        }

        /// Same name and size. When the size isn't known (0), the name alone, but only if exactly one
        /// record has it: camera names like IMG_0001.MOV repeat across phones and years.
        func match(fileName: String, fileSize: Int64) -> Record? {
            if fileSize > 0 {
                return byFingerprint[WatchHistory.fingerprint(fileName: fileName, fileSize: fileSize)]
            }
            let candidates = byName[fileName.lowercased()] ?? []
            return candidates.count == 1 ? candidates[0] : nil
        }

        mutating func insert(_ record: Record, fileName: String, fileSize: Int64) {
            byFingerprint[WatchHistory.fingerprint(fileName: fileName, fileSize: fileSize)] = record
            byName[fileName.lowercased(), default: []].append(record)
        }
    }
}
