import Foundation
import Observation

/// One play-through of a file on the mpv engine: owns the render view and player, resumes,
/// and records progress the same way PlaybackSession does for AVKit.
@MainActor
@Observable
final class MPVPlaybackSession {
    let renderView = MPVRenderView(frame: .zero)
    let player: MPVPlayer
    private let item: MediaItem
    private let store: LibraryStore
    @ObservationIgnored private var lastSaved: Double = 0

    var state: MPVPlayerState { player.state }

    /// `startAt` nil or 0 plays from the beginning.
    init?(item: MediaItem, url: URL, store: LibraryStore, startAt: Double?) {
        guard let player = MPVPlayer(layer: renderView.metalLayer) else { return nil }
        self.player = player
        self.item = item
        self.store = store

        let startAt = startAt ?? 0
        lastSaved = startAt
        player.state.onPositionChange = { [weak self] seconds in
            guard let self, abs(seconds - self.lastSaved) >= 5 else { return }
            self.lastSaved = seconds
            self.store.saveProgress(self.item, seconds: seconds)
        }
        player.state.onEnd = { [weak self] in
            guard let self else { return }
            self.store.saveProgress(self.item, seconds: self.item.duration ?? self.state.duration)
        }
        player.apply(PlaybackPreferences.videoQuality)
        player.setAudioFilter(PlaybackPreferences.sound.mpvAudioFilter)
        player.load(url, startAt: startAt)
    }

    var currentTime: Double { player.currentPosition }
    func seek(to seconds: Double) { player.seek(to: seconds) }
    func updateSound(_ settings: SoundSettings) { player.setAudioFilter(settings.mpvAudioFilter) }

    /// Call when the player closes.
    func end() {
        let position = player.currentPosition
        if position > 0, !state.reachedEnd {
            store.saveProgress(item, seconds: position)
        }
        player.shutdown()
    }
}
