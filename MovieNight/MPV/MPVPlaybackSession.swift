import Foundation
import Observation
import SwiftUI

/// One play-through of a file on the mpv engine: owns the render view and player, resumes,
/// and records progress the same way PlaybackSession does for AVKit.
@MainActor
@Observable
final class MPVPlaybackSession: PlayerEngine {
    let renderView = MPVRenderView(frame: .zero)
    let player: MPVPlayer
    private let item: MediaItem
    private let store: LibraryStore
    @ObservationIgnored private var lastSaved: Double = 0
    @ObservationIgnored private var pictureInPicture: MPVPictureInPicture?

    var state: PlayerState { player.state }
    var surface: AnyView { AnyView(MPVSurface(view: renderView)) }
    let supportsAirPlayVideo = false

    /// `startAt` nil or 0 plays from the beginning.
    init?(item: MediaItem, url: URL, store: LibraryStore, startAt: Double?) {
        guard let player = MPVPlayer(layer: renderView.metalLayer) else { return nil }
        self.player = player
        self.item = item
        self.store = store

        let startAt = startAt ?? 0
        lastSaved = startAt
        player.state.onPositionChange = { [weak self] seconds in
            guard let self else { return }
            self.pictureInPicture?.sync(position: seconds, isPaused: self.state.isPaused)
            guard abs(seconds - self.lastSaved) >= 5 else { return }
            self.lastSaved = seconds
            self.store.saveProgress(self.item, seconds: seconds)
        }
        player.state.onEnd = { [weak self] in
            guard let self else { return }
            self.store.saveProgress(self.item, seconds: self.item.duration ?? self.state.duration)
        }
        player.apply(PlaybackPreferences.videoQuality)
        player.apply(SubtitleStyle.current)
        player.setAudioFilter(PlaybackPreferences.sound.mpvAudioFilter)
        player.load(url, startAt: startAt)

        if MPVPictureInPicture.isSupported {
            let pip = MPVPictureInPicture(player: player)
            renderView.metalLayer.addSublayer(pip.displayLayer)
            pictureInPicture = pip
            state.isPictureInPicturePossible = true
        }
    }

    func setPaused(_ paused: Bool) {
        player.setPaused(paused)
        pictureInPicture?.sync(position: state.position, isPaused: paused)
    }
    func seek(to seconds: Double) { player.seek(to: seconds) }
    func setRate(_ rate: Double) { player.setSpeed(rate) }

    func setVolume(_ volume: Double) {
        state.volume = volume
        player.setVolume(volume)
    }

    func selectAudio(_ id: Int) { player.selectAudio(id) }
    func selectSubtitle(_ id: Int?) { player.selectSubtitle(id) }

    func setSubtitleDelay(_ seconds: Double) {
        state.subtitleDelay = seconds
        player.setSubtitleDelay(seconds)
    }

    func applySubtitleStyle(_ style: SubtitleStyle) { player.apply(style) }
    func updateSound(_ settings: SoundSettings) { player.setAudioFilter(settings.mpvAudioFilter) }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isActive {
            pictureInPicture.stop()
        } else {
            Task { _ = await pictureInPicture.start() }
        }
    }

    /// Metal can't draw from the background, so video is switched off and sound keeps playing.
    /// Picture in Picture draws on the CPU, so it carries on.
    func setBackgrounded(_ backgrounded: Bool) {
        pictureInPicture?.isAppInBackground = backgrounded
        if pictureInPicture?.isActive == true { return }
        player.setVideoEnabled(!backgrounded)
    }

    /// Call when the player closes.
    func end() {
        pictureInPicture?.tearDown()
        let position = player.currentPosition
        if position > 0, !state.reachedEnd {
            store.saveProgress(item, seconds: position)
        }
        player.shutdown()
    }
}
