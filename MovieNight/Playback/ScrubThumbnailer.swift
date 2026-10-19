import AVFoundation
import Foundation
import Libmpv
import os

/// Small frames for the preview above the timeline while scrubbing.
protocol ScrubThumbnailer: AnyObject, Sendable {
    /// A frame near `seconds`, or nil. Requests overtaken by a newer one may return nil early.
    func frame(at seconds: Double) async -> CGImage?
    func close()
}

/// Apple's frame grabber, for MP4/MOV. Lands on the nearest keyframe within a second, which is fast.
/// AVAssetImageGenerator is safe to use from any thread; it just isn't marked Sendable.
final class AssetScrubThumbnailer: ScrubThumbnailer, @unchecked Sendable {
    private let generator: AVAssetImageGenerator

    init(asset: AVAsset) {
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
    }

    func frame(at seconds: Double) async -> CGImage? {
        try? await generator.image(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)).image
    }

    func close() { generator.cancelAllCGImageGeneration() }
}

/// A second, headless mpv for MKV and the other extended formats: no sound, no window, decoding
/// small frames (scaled down by FFmpeg) on keyframe seeks. Only the newest request is worked on.
final class MPVScrubThumbnailer: ScrubThumbnailer, @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "movienight.scrub-thumbnails", qos: .userInitiated)
    // Touched only on `queue`.
    private var mpv: MPVHandle?
    private var loaded = false
    /// Bumped by every request; queued work for an older one gives up.
    private let latest = OSAllocatedUnfairLock(initialState: 0)

    init(url: URL) {
        self.url = url
    }

    func frame(at seconds: Double) async -> CGImage? {
        let ticket = latest.withLock { value -> Int in value += 1; return value }
        let box = await withCheckedContinuation { (continuation: CheckedContinuation<ImageBox, Never>) in
            queue.async {
                guard self.latest.withLock({ $0 }) == ticket else { return continuation.resume(returning: ImageBox(nil)) }
                continuation.resume(returning: ImageBox(self.render(at: seconds)))
            }
        }
        return box.image
    }

    func close() {
        queue.sync {
            mpv?.destroy()
            mpv = nil
        }
    }

    private func render(at seconds: Double) -> CGImage? {
        guard let mpv = prepared() else { return nil }
        mpv.command(["seek", String(format: "%.2f", max(seconds, 0)), "absolute+keyframes"])
        guard waitFor(MPV_EVENT_PLAYBACK_RESTART, on: mpv, timeout: 2) else { return nil }
        return MPVProbe.rawFrame(mpv)
    }

    private func prepared() -> MPVHandle? {
        if let mpv, loaded { return mpv }
        guard let handle = MPVHandle() else { return nil }
        let options = [
            ("config", "no"), ("load-scripts", "no"), ("terminal", "no"), ("ytdl", "no"),
            ("ao", "null"), ("vo", "null"), ("aid", "no"), ("sid", "no"), ("pause", "yes"),
            ("hwdec", "no"), ("hr-seek", "no"), ("vf", "scale=w=320:h=-2"), ("demuxer-readahead-secs", "0"),
        ]
        for (name, value) in options { handle.setOption(name, value) }
        guard handle.initialize() else { handle.destroy(); return nil }
        handle.command(["loadfile", url.path])
        guard waitFor(MPV_EVENT_PLAYBACK_RESTART, on: handle, timeout: 10) else { handle.destroy(); return nil }
        mpv = handle
        loaded = true
        return handle
    }

    private func waitFor(_ wanted: mpv_event_id, on mpv: MPVHandle, timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            guard let event = mpv_wait_event(mpv.raw, 0.25) else { continue }
            switch event.pointee.event_id {
            case wanted: return true
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN: return false
            default: continue
            }
        }
        return false
    }
}

/// CGImage isn't marked Sendable; it's immutable, so passing it across the continuation is safe.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
}
