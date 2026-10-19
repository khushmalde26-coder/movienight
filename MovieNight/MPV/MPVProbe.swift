import Foundation
import Libmpv

/// Reads metadata and grabs a frame from files AVFoundation can't open, using a headless mpv
/// that decodes one frame at 10% and writes it as a JPEG (`vo=image`).
enum MPVProbe {
    struct Result: Sendable {
        var metadata: VideoMetadata
        var frameFile: URL?
    }

    /// Blocking work runs on a GCD queue so it doesn't tie up a Swift concurrency thread.
    static func probe(_ url: URL, frameDirectory: URL) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: probeSync(url, frameDirectory: frameDirectory))
            }
        }
    }

    private static func probeSync(_ url: URL, frameDirectory: URL) -> Result {
        var metadata = VideoMetadata(isPlayable: false)
        guard let mpv = MPVHandle() else { return Result(metadata: metadata) }
        defer { mpv.destroy() }

        try? FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        let options = [
            ("config", "no"), ("load-scripts", "no"), ("terminal", "no"), ("ytdl", "no"),
            ("idle", "no"), ("ao", "null"), ("hwdec", "no"),
            ("vo", "image"), ("vo-image-format", "jpg"), ("vo-image-jpeg-quality", "85"),
            ("vo-image-outdir", frameDirectory.path), ("frames", "1"), ("start", "10%"),
        ]
        for (name, value) in options { mpv.setOption(name, value) }
        guard mpv.initialize() else { return Result(metadata: metadata) }
        mpv.command(["loadfile", url.path])

        var loaded = false
        let deadline = Date.now.addingTimeInterval(20)
        events: while Date.now < deadline {
            guard let event = mpv_wait_event(mpv.raw, 1) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                loaded = true
                read(mpv, into: &metadata)
            case MPV_EVENT_VIDEO_RECONFIG, MPV_EVENT_AUDIO_RECONFIG, MPV_EVENT_PLAYBACK_RESTART:
                if loaded { read(mpv, into: &metadata) }
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                break events
            default:
                continue
            }
        }
        // Audio-only files (an .ogg of music) aren't videos for this library.
        metadata.isPlayable = loaded && metadata.width != nil

        let frame = (try? FileManager.default.contentsOfDirectory(at: frameDirectory, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "jpg" }
        return Result(metadata: metadata, frameFile: frame)
    }

    private static func read(_ mpv: MPVHandle, into metadata: inout VideoMetadata) {
        if let duration = mpv.double("duration"), duration > 0 {
            metadata.duration = duration
        }
        // dw/dh include the pixel aspect ratio (anamorphic DVDs); rotation is applied separately.
        if var width = mpv.int("video-params/dw"), var height = mpv.int("video-params/dh") {
            if let rotate = mpv.int("video-params/rotate"), rotate % 180 == 90 {
                swap(&width, &height)
            }
            metadata.width = width
            metadata.height = height
        }
        if let fps = mpv.double("container-fps"), fps > 0 {
            metadata.frameRate = fps
        }
        if let format = mpv.string("video-format") {
            metadata.videoCodec = CodecName.fromFFmpeg(format)
        }
        if let gamma = mpv.string("video-params/gamma") {
            metadata.isHDR = gamma == "pq" || gamma == "hlg"
        }
        if let channels = mpv.int("audio-params/channel-count"), channels > 0 {
            metadata.audioChannels = channels
        }
        if metadata.recordedAt == nil, let created = mpv.string("metadata/by-key/creation_time") {
            metadata.recordedAt = parseDate(created)
        }
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
