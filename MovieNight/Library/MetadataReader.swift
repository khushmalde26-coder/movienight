import AVFoundation
import CoreMedia

struct VideoMetadata: Sendable {
    var duration: Double?
    /// The date embedded by the camera. Survives copying between drives, unlike file dates.
    var recordedAt: Date?
    var isPlayable: Bool
    /// Display size, with the track's rotation applied (phone portrait video is stored landscape + a transform).
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var videoCodec: String?
    var isHDR = false
    var audioChannels: Int?
    var chapters: [Chapter] = []
}

enum MetadataReader {
    /// Bump when this reader learns to extract something new, so existing items get re-read.
    static let version = 3

    static func read(_ url: URL) async -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        do {
            let (duration, isPlayable, creation) = try await asset.load(.duration, .isPlayable, .creationDate)
            var result = VideoMetadata(isPlayable: isPlayable)
            let seconds = duration.seconds
            result.duration = seconds.isFinite && seconds > 0 ? seconds : nil
            if let creation {
                result.recordedAt = try? await creation.load(.dateValue)
            }

            if let video = try await asset.loadTracks(withMediaType: .video).first {
                let (size, transform, fps, formats, characteristics) = try await video.load(
                    .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions, .mediaCharacteristics
                )
                let display = size.applying(transform)
                result.width = Int(abs(display.width).rounded())
                result.height = Int(abs(display.height).rounded())
                result.frameRate = fps > 0 ? Double(fps) : nil
                result.videoCodec = formats.first.map { codecName(CMFormatDescriptionGetMediaSubType($0)) }
                result.isHDR = characteristics.contains(.containsHDRVideo)
            }

            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let format = try await audio.load(.formatDescriptions).first,
               let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                result.audioChannels = Int(description.pointee.mChannelsPerFrame)
            }
            result.chapters = await chapters(of: asset)
            return result
        } catch {
            return VideoMetadata(isPlayable: false)
        }
    }

    /// Chapter tracks in MP4/MOV/M4V, titled in the user's language when the file has several.
    static func chapters(of asset: AVAsset) async -> [Chapter] {
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
        else { return [] }
        var chapters: [Chapter] = []
        for (index, group) in groups.enumerated() {
            let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
            let title = (try? await titleItem?.load(.stringValue)) ?? nil
            chapters.append(Chapter(title: title ?? "Chapter \(index + 1)", start: group.timeRange.start.seconds))
        }
        return chapters.filter { $0.start.isFinite }
    }

    static func codecName(_ code: FourCharCode) -> String {
        let fourCC = String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
        return CodecName.fromFourCC(fourCC)
    }
}
