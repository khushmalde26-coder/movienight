import Accelerate
import CoreVideo
import Foundation
import Libmpv
import os

/// Draws mpv's video into pixel buffers on the CPU. Picture in Picture needs frames it can put in a
/// sample-buffer layer, and mpv's normal output draws straight to Metal, so while PiP is up the
/// video output is switched to `libmpv` and rendered here, at PiP size.
final class MPVSoftwareRenderer: @unchecked Sendable {
    private let mpv: MPVHandle
    private var context: OpaquePointer?
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    /// mpv's update callback runs on its own thread.
    private let needsRender = OSAllocatedUnfairLock(initialState: false)
    // Never written after creation; mpv only reads them.
    nonisolated(unsafe) private static let apiType = strdup(MPV_RENDER_API_TYPE_SW)!
    nonisolated(unsafe) private static let pixelFormat = strdup("bgr0")!

    init(mpv: MPVHandle) {
        self.mpv = mpv
    }

    var isRunning: Bool { context != nil }

    /// Creates the render context, then moves mpv's video output onto it.
    func start() -> Bool {
        guard context == nil else { return true }
        var params = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(Self.apiType)),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        var created: OpaquePointer?
        guard mpv_render_context_create(&created, mpv.raw, &params) >= 0, let created else { return false }
        context = created
        mpv_render_context_set_update_callback(created, { info in
            guard let info else { return }
            Unmanaged<MPVSoftwareRenderer>.fromOpaque(info).takeUnretainedValue().needsRender.withLock { $0 = true }
        }, Unmanaged.passUnretained(self).toOpaque())
        mpv.setProperty("vo", "libmpv")
        return true
    }

    /// The next frame, if mpv has one, fitted into `width` × `height` with black bars as needed.
    func renderFrame(width: Int, height: Int) -> CVPixelBuffer? {
        guard let context, width > 0, height > 0 else { return nil }
        let wanted = needsRender.withLock { value -> Bool in defer { value = false }; return value }
        guard wanted else { return nil }
        let flags = mpv_render_context_update(context)
        guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0, let buffer = makeBuffer(width: width, height: height) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var size: [Int32] = [Int32(width), Int32(height)]
        var stride = CVPixelBufferGetBytesPerRow(buffer)
        let result = size.withUnsafeMutableBufferPointer { sizePointer in
            withUnsafeMutablePointer(to: &stride) { stridePointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePointer.baseAddress!)),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(Self.pixelFormat)),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_render(context, &params)
            }
        }
        guard result >= 0 else { return nil }
        // "bgr0" leaves the fourth byte undefined (usually 0, which would read as transparent).
        var image = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: stride)
        vImageOverwriteChannelsWithScalar_ARGB8888(255, &image, &image, 0x1, vImage_Flags(kvImageNoFlags))
        return buffer
    }

    /// Hands video back to `vo` (the GPU output, or null in the background) and frees the context.
    func stop(restoring vo: String) {
        guard let context else { return }
        mpv.setProperty("vo", vo)
        // Let mpv leave the libmpv output before its context goes; freeing it first would disable video.
        let deadline = Date.now.addingTimeInterval(1)
        while mpv.string("current-vo") == "libmpv", Date.now < deadline { usleep(10_000) }
        mpv_render_context_set_update_callback(context, nil, nil)
        mpv_render_context_free(context)
        self.context = nil
        pool = nil
    }

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize != (width, height) {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
            pool = created
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
