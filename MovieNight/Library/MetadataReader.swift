import AVFoundation

struct VideoMetadata: Sendable {
    var duration: Double?
    /// The date embedded by the camera. Survives copying between drives, unlike file dates.
    var recordedAt: Date?
    var isPlayable: Bool
}

enum MetadataReader {
    static func read(_ url: URL) async -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        do {
            let (duration, isPlayable, creation) = try await asset.load(.duration, .isPlayable, .creationDate)
            var recordedAt: Date?
            if let creation {
                recordedAt = try? await creation.load(.dateValue)
            }
            let seconds = duration.seconds
            return VideoMetadata(duration: seconds.isFinite && seconds > 0 ? seconds : nil, recordedAt: recordedAt, isPlayable: isPlayable)
        } catch {
            return VideoMetadata(duration: nil, recordedAt: nil, isPlayable: false)
        }
    }
}
