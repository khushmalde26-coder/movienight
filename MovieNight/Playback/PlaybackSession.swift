import AVFoundation
import Observation

/// One play-through of one item on AVKit: owns the AVPlayer, resumes, and records progress.
/// MPVPlaybackSession is the equivalent for files AVFoundation can't open.
@MainActor
@Observable
final class PlaybackSession {
    let player: AVPlayer
    private let item: MediaItem
    private let store: LibraryStore
    private var timeObserver: Any?

    init(item: MediaItem, url: URL, store: LibraryStore) {
        self.item = item
        self.store = store
        self.player = AVPlayer(url: url)

        if let resume = item.resumePosition() {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.record(time.seconds)
            }
        }
        player.play()
    }

    private func record(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        store.saveProgress(item, seconds: seconds)
    }

    /// Call when the player closes. Not done in deinit because deinit isn't main-actor isolated.
    func end() {
        record(player.currentTime().seconds)
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}
