import AVFoundation
import Observation

/// One play-through of one item: owns the AVPlayer, resumes, and records progress.
/// TODO(phase 3): put AVPlayer behind a PlaybackEngine protocol with a VLCKit/libmpv
/// implementation for files where `isPlayable == false`.
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

        if !item.isFinished, item.progressSeconds > 5 {
            player.seek(to: CMTime(seconds: item.progressSeconds, preferredTimescale: 600))
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
