import QuartzCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// MoltenVK sometimes sets drawableSize to 1×1 to force a present, which causes flicker.
/// Workaround from mpv (https://github.com/mpv-player/mpv/pull/13651) and the MPVKit demo.
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

#if os(macOS)
/// The surface mpv renders into (passed to mpv as `wid`).
final class MPVRenderView: NSView {
    let metalLayer = MPVMetalLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.framebufferOnly = true
        layer = metalLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.sublayers?.forEach { $0.frame = metalLayer.bounds }
    }
}
#else
final class MPVRenderView: UIView {
    override class var layerClass: AnyClass { MPVMetalLayer.self }
    var metalLayer: MPVMetalLayer { layer as! MPVMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.framebufferOnly = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        // The Picture in Picture layer sits on top, empty except while PiP is showing.
        metalLayer.sublayers?.forEach { $0.frame = bounds }
    }
}
#endif

#if os(macOS)
struct MPVSurface: NSViewRepresentable {
    let view: MPVRenderView
    func makeNSView(context: Context) -> MPVRenderView { view }
    func updateNSView(_ nsView: MPVRenderView, context: Context) {}
}
#else
struct MPVSurface: UIViewRepresentable {
    let view: MPVRenderView
    func makeUIView(context: Context) -> MPVRenderView { view }
    func updateUIView(_ uiView: MPVRenderView, context: Context) {}
}
#endif
