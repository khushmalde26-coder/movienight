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
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable (Double?) -> Void) {
            command.isEnabled = true
            targets.append((command, Self.addTarget(to: command, action)))
        }
        on(center.playCommand) { [weak engine] _ in engine?.setPaused(false) }
        on(center.pauseCommand) { [weak engine] _ in engine?.setPaused(true) }
        on(center.togglePlayPauseCommand) { [weak engine] _ in engine?.togglePause() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        on(center.skipForwardCommand) { [weak engine] _ in engine?.seek(by: 10) }
        on(center.skipBackwardCommand) { [weak engine] _ in engine?.seek(by: -10) }
        on(center.changePlaybackPositionCommand) { [weak engine] position in
            if let position { engine?.seek(to: position) }
        }

        #if os(iOS)
        if let image { artwork = Self.artwork(UIImage(cgImage: image)) }
        #endif
    }

    // The system calls these back on its own queues. Built outside the main actor so the closures
    // don't carry main-actor isolation, which crashes when they're called from another thread.

    nonisolated private static func addTarget(to command: MPRemoteCommand,
                                              _ action: @escaping @MainActor @Sendable (Double?) -> Void) -> Any {
        command.addTarget { event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            if Thread.isMainThread {
                MainActor.assumeIsolated { action(position) }
            } else {
                Task { @MainActor in action(position) }
            }
            return .success
        }
    }

    #if os(iOS)
    nonisolated static func artwork(_ picture: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: picture.size) { @Sendable _ in picture }
    }
    #endif

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
