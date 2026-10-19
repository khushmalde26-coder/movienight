import AVFoundation
import SwiftUI

/// The Movie Night animation, once per launch: a ring that resolves into the logo, then a fade into the app.
/// A tap skips it; with Reduce Motion on it's skipped altogether.
struct StartupView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layerView = PlayerLayerView()

    var body: some View {
        ZStack {
            Theme.background
            PlayerLayerSurface(view: layerView)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityElement()
        .accessibilityLabel("Movie Night")
        .accessibilityHint("Double-tap to skip")
        .accessibilityAction { onFinish() }
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion, let url = Bundle.main.url(forResource: "Startup", withExtension: "mp4") else {
            onFinish()
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        layerView.playerLayer.videoGravity = .resizeAspectFill
        layerView.playerLayer.player = player
        player.play()
        // Ends at the last frame, or after 8 s if anything stalls; leaving early (a tap) cancels this.
        let deadline = Date.now.addingTimeInterval(8)
        while !Task.isCancelled, Date.now < deadline {
            let duration = item.duration.seconds, now = item.currentTime().seconds
            if duration.isFinite, duration > 0, now >= duration - 0.05 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        player.pause()
        if !Task.isCancelled { onFinish() }
    }
}
