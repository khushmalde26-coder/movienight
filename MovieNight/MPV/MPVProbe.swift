import Foundation
import ImageIO
import Libmpv
import UniformTypeIdentifiers

/// Reads metadata and grabs a frame from files AVFoundation can't open, using a headless mpv
/// paused at 10%. MPVKit's FFmpeg has no image encoders, so `vo=image` can't write the frame:
/// it's taken raw with `screenshot-raw` and written as a JPEG with ImageIO instead.
enum MPVProbe {
    struct Result: Sendable {
        var metadata: VideoMetadata
        var frameFile: URL?
    }

    /// Blocking work runs on a GCD queue so it doesn't tie up a Swift concurrency thread.
    /// Without `grabFrame` (the file already has artwork) it skips the seek to 10% and the frame,
    /// which is most of the time on large 4K files.
    static func probe(_ url: URL, frameDirectory: URL, grabFrame: Bool = true) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: probeSync(url, frameDirectory: frameDirectory, grabFrame: grabFrame))
            }
        }
    }

    private static func probeSync(_ url: URL, frameDirectory: URL, grabFrame: Bool) -> Result {
        var metadata = VideoMetadata(isPlayable: false)
        guard let mpv = MPVHandle() else { return Result(metadata: metadata) }
        defer { mpv.destroy() }

        try? FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        // idle stays on (libmpv's default): with it off, mpv shuts down if the core starts before
        // `loadfile` lands, which happens on slower devices. The loop below ends on END_FILE instead.
        let options = [
            ("config", "no"), ("load-scripts", "no"), ("terminal", "no"), ("ytdl", "no"),
            ("ao", "null"), ("vo", "null"), ("hwdec", "no"),
            ("pause", "yes"), ("start", grabFrame ? "10%" : "0"),
        ]
        for (name, value) in options { mpv.setOption(name, value) }
        guard mpv.initialize() else { return Result(metadata: metadata) }
        mpv.command(["loadfile", url.path])

        var loaded = false
        var frame: URL?
        let deadline = Date.now.addingTimeInterval(20)
        events: while Date.now < deadline {
            guard let event = mpv_wait_event(mpv.raw, 1) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                loaded = true
                read(mpv, into: &metadata)
            case MPV_EVENT_VIDEO_RECONFIG, MPV_EVENT_AUDIO_RECONFIG:
                if loaded { read(mpv, into: &metadata) }
            case MPV_EVENT_PLAYBACK_RESTART:
                // Paused on the first frame at the start position: everything is known now.
                guard loaded else { continue }
                read(mpv, into: &metadata)
                if grabFrame { frame = writeFrame(mpv, to: frameDirectory.appending(path: "frame.jpg")) }
                break events
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                break events
            default:
                continue
            }
        }
        // Audio-only files (an .ogg of music) aren't videos for this library.
        metadata.isPlayable = loaded && metadata.width != nil
        return Result(metadata: metadata, frameFile: frame)
    }

    private static func writeFrame(_ mpv: MPVHandle, to url: URL) -> URL? {
        guard let image = rawFrame(mpv),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// The current frame after video filters but before subtitles and OSD, from BGR0 pixels.
    static func rawFrame(_ mpv: MPVHandle) -> CGImage? {
        let command = ["screenshot-raw", "video"]
        var args: [UnsafePointer<CChar>?] = command.map { UnsafePointer(strdup($0)) } + [nil]
        defer { for arg in args { free(UnsafeMutablePointer(mutating: arg)) } }
        var node = mpv_node()
        guard mpv_command_ret(mpv.raw, &args, &node) >= 0 else { return nil }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list?.pointee else { return nil }

        var width = 0, height = 0, stride = 0
        var pixels: Data?
        for index in 0..<Int(list.num) {
            guard let key = list.keys?[index] else { continue }
            let value = list.values[index]
            switch String(cString: key) {
            case "w": width = Int(value.u.int64)
            case "h": height = Int(value.u.int64)
            case "stride": stride = Int(value.u.int64)
            case "data":
                if value.format == MPV_FORMAT_BYTE_ARRAY, let bytes = value.u.ba?.pointee, let data = bytes.data {
                    pixels = Data(bytes: data, count: bytes.size)
                }
            default: continue
            }
        }
        guard width > 0, height > 0, stride >= width * 4, let pixels, pixels.count >= stride * height,
              let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return image
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
        // The soundtrack mpv picked (the file's default), else any track that has it.
        metadata.spatialAudio = SpatialAudio.fromProfile(mpv.string("current-tracks/audio/codec-profile"))
        if metadata.spatialAudio == nil, let count = mpv.int("track-list/count") {
            metadata.spatialAudio = (0..<count).lazy
                .filter { mpv.string("track-list/\($0)/type") == "audio" }
                .compactMap { SpatialAudio.fromProfile(mpv.string("track-list/\($0)/codec-profile")) }
                .first
        }
        if let count = mpv.int("chapter-list/count"), count > 0 {
            metadata.chapters = (0..<count).compactMap { index in
                guard let start = mpv.double("chapter-list/\(index)/time") else { return nil }
                return Chapter(title: mpv.string("chapter-list/\(index)/title") ?? "Chapter \(index + 1)", start: start)
            }
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
