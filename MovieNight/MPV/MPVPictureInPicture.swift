import AVFoundation
import AVKit
import QuartzCore

/// Picture in Picture for mpv files. While it's showing, mpv renders on the CPU at PiP size
/// (MPVSoftwareRenderer) into a sample-buffer layer that the system floats over other apps.
@MainActor
final class MPVPictureInPicture: NSObject {
    let displayLayer = AVSampleBufferDisplayLayer()
    private let player: MPVPlayer
    private let renderer: MPVSoftwareRenderer
    private var controller: AVPictureInPictureController?
    private var frameTimer: Timer?
    private var renderSize = CGSize(width: 960, height: 540)
    private var timebase: CMTimebase?
    private var formatDescription: CMVideoFormatDescription?
    /// What to give video back to when PiP ends: Metal in the foreground, nothing in the background.
    var isAppInBackground = false

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var isActive: Bool { controller?.isPictureInPictureActive ?? false }

    init(player: MPVPlayer) {
        self.player = player
        renderer = MPVSoftwareRenderer(mpv: player.handle)
        super.init()
        displayLayer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            displayLayer.controlTimebase = timebase
            self.timebase = timebase
        }
        guard Self.isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        self.controller = controller
    }

    /// Switches mpv to frames PiP can show, then asks the system to start once it can.
    func start() async -> Bool {
        guard let controller, renderer.start() else { return false }
        startFrames()
        // PiP becomes possible once the layer has a frame; give it a moment.
        for _ in 0..<30 {
            if controller.isPictureInPicturePossible {
                controller.startPictureInPicture()
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        finish()
        return false
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    /// The player is closing: give up PiP and the render context before mpv goes away.
    func tearDown() {
        controller?.stopPictureInPicture()
        if renderer.isRunning { finish() }
    }

    /// Keeps the PiP window's clock and play/pause button in step with mpv.
    func sync(position: Double, isPaused: Bool) {
        guard let timebase, renderer.isRunning else { return }
        let current = CMTimebaseGetTime(timebase).seconds
        if abs(current - position) > 0.5 || !current.isFinite {
            CMTimebaseSetTime(timebase, time: CMTime(seconds: position, preferredTimescale: 600))
        }
        CMTimebaseSetRate(timebase, rate: isPaused ? 0 : player.state.rate)
        controller?.invalidatePlaybackState()
    }

    private func startFrames() {
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        sync(position: player.state.position, isPaused: player.state.isPaused)
    }

    private func renderFrame() {
        // The PiP window is small; render at its size (in pixels, capped) rather than the video's.
        let width = min(Int(renderSize.width), 1280) & ~1, height = min(Int(renderSize.height), 720) & ~1
        guard let pixels = renderer.renderFrame(width: width, height: height) else { return }
        if formatDescription == nil || CMVideoFormatDescriptionGetDimensions(formatDescription!).width != Int32(width) {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: formatDescription,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }

    private func finish() {
        frameTimer?.invalidate()
        frameTimer = nil
        renderer.stop(restoring: "gpu-next")
        if isAppInBackground { player.setVideoEnabled(false) }
        displayLayer.flushAndRemoveImage()
        formatDescription = nil
    }
}

extension MPVPictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated {
            player.setPaused(!playing)
            sync(position: player.state.position, isPaused: !playing)
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            let duration = player.state.duration
            return duration > 0 ? CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
                : CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { player.state.isPaused }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        MainActor.assumeIsolated {
            renderSize = CGSize(width: CGFloat(newRenderSize.width), height: CGFloat(newRenderSize.height))
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated {
            player.seek(by: skipInterval.seconds)
        }
        completionHandler()
    }
}

extension MPVPictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { player.state.isPictureInPictureActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            player.state.isPictureInPictureActive = false
            finish()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
