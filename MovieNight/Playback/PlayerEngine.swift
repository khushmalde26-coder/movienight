import Observation
import SwiftUI

struct MediaTrack: Identifiable, Hashable, Sendable {
    var id: Int
    var label: String
    /// ISO 639 code when the file says, used to remember language preferences.
    var language: String?
    var isSelected: Bool
}

/// What the controls show, for either engine. Updated on the main actor.
@MainActor
@Observable
final class PlayerState {
    var position: Double = 0
    var duration: Double = 0
    var isPaused = false
    var isBuffering = false
    var reachedEnd = false
    var rate: Double = 1
    /// Player volume, 0...1. Separate from the device volume.
    var volume: Double = 1
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var subtitleDelay: Double = 0
    /// Subtitle text for engines that leave drawing to SwiftUI (Apple's player). mpv draws its own.
    var subtitleText: String?
    var isPictureInPicturePossible = false
    var isPictureInPictureActive = false

    @ObservationIgnored var onPositionChange: ((Double) -> Void)?
    @ObservationIgnored var onEnd: (() -> Void)?
}

/// One play-through on one engine. Both Apple's player and mpv implement this, so the same
/// controls, gestures, lock-screen commands and settings drive either.
@MainActor
protocol PlayerEngine: AnyObject {
    var state: PlayerState { get }
    /// The video surface.
    var surface: AnyView { get }
    /// Video can go to an Apple TV. mpv can only send sound over AirPlay.
    var supportsAirPlayVideo: Bool { get }

    func setPaused(_ paused: Bool)
    func seek(to seconds: Double)
    func setRate(_ rate: Double)
    func setVolume(_ volume: Double)
    func selectAudio(_ id: Int)
    func selectSubtitle(_ id: Int?)
    func setSubtitleDelay(_ seconds: Double)
    func applySubtitleStyle(_ style: SubtitleStyle)
    func updateSound(_ settings: SoundSettings)
    func togglePictureInPicture()
    /// The app left or returned to the screen: keep sound going without drawing video.
    func setBackgrounded(_ backgrounded: Bool)
    /// Saves progress and releases the player. Call once, when the player closes.
    func end()
}

extension PlayerEngine {
    func togglePause() { setPaused(!state.isPaused) }
    func seek(by seconds: Double) {
        seek(to: min(max(state.position + seconds, 0), max(state.duration - 1, 0)))
    }
}
