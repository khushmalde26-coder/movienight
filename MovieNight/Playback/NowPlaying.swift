import MediaPlayer
#if os(iOS)
import UIKit
#endif

/// Lock screen, Control Center, headphone and keyboard media keys, for both engines.
/// (Apple's own player screen did this for MP4/MOV; the custom controls need it done by hand.)
@MainActor
final class NowPlaying {
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artwork: MPMediaItemArtwork?

    func start(engine: any PlayerEngine, artwork image: CGImage?) {
        stop()
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let token = command.addTarget { [weak engine] event in
                guard engine != nil else { return .noActionableNowPlayingItem }
                // Remote commands arrive on the main thread.
                MainActor.assumeIsolated { action(event) }
                return .success
            }
            targets.append((command, token))
        }
        on(center.playCommand) { [weak engine] _ in engine?.setPaused(false) }
        on(center.pauseCommand) { [weak engine] _ in engine?.setPaused(true) }
        on(center.togglePlayPauseCommand) { [weak engine] _ in engine?.togglePause() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        on(center.skipForwardCommand) { [weak engine] _ in engine?.seek(by: 10) }
        on(center.skipBackwardCommand) { [weak engine] _ in engine?.seek(by: -10) }
        on(center.changePlaybackPositionCommand) { [weak engine] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { engine?.seek(to: event.positionTime) }
        }

        #if os(iOS)
        if let image {
            let picture = UIImage(cgImage: image)
            artwork = MPMediaItemArtwork(boundsSize: picture.size) { _ in picture }
        }
        #endif
    }

    func update(title: String, state: PlayerState) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPaused ? 0.0 : state.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        #if os(macOS)
        center.playbackState = state.isPaused ? .paused : .playing
        #endif
    }

    func stop() {
        for (command, token) in targets { command.removeTarget(token) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }
}
