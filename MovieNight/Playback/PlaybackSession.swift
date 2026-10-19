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
    @ObservationIgnored private let sound: SoundProcessor

    /// `startAt` nil or 0 plays from the beginning.
    init(item: MediaItem, url: URL, store: LibraryStore, startAt: Double?) {
        self.item = item
        self.store = store
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.sound = SoundProcessor(settings: PlaybackPreferences.sound)

        if let startAt, startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
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

        // Dialogue boost, night mode and balance run in an audio tap on the file's sound track.
        let processor = sound
        Task {
            if let mix = await processor.audioMix(for: asset) { playerItem.audioMix = mix }
        }
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func updateSound(_ settings: SoundSettings) {
        sound.update(settings)
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
