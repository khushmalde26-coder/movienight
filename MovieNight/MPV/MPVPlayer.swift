import Foundation
import Libmpv
import Observation
import QuartzCore

struct MPVTrack: Identifiable, Hashable, Sendable {
    var id: Int
    var label: String
    var isSelected: Bool
}

/// What the controls show. Updated on the main actor from mpv's property-change events.
@MainActor
@Observable
final class MPVPlayerState {
    var position: Double = 0
    var duration: Double = 0
    var isPaused = false
    var isBuffering = false
    var reachedEnd = false
    var audioTracks: [MPVTrack] = []
    var subtitleTracks: [MPVTrack] = []

    @ObservationIgnored var onPositionChange: ((Double) -> Void)?
    @ObservationIgnored var onEnd: (() -> Void)?
}

/// Plays one file through libmpv (FFmpeg decoding, VideoToolbox hardware decode, Vulkan-on-Metal output).
final class MPVPlayer: @unchecked Sendable {
    private let mpv: MPVHandle
    private let eventQueue = DispatchQueue(label: "movienight.mpv.events", qos: .userInitiated)
    let state: MPVPlayerState

    @MainActor
    init?(layer: CALayer) {
        guard let mpv = MPVHandle() else { return nil }
        self.mpv = mpv
        self.state = MPVPlayerState()

        // mpv takes the layer's address as an integer window id.
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(mpv.raw, "wid", MPV_FORMAT_INT64, &wid)
        let options = [
            ("config", "no"), ("load-scripts", "no"), ("osc", "no"), ("ytdl", "no"),
            ("input-default-bindings", "no"), ("input-vo-keyboard", "no"),
            ("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"), ("keep-open", "yes"),
            ("sub-auto", "fuzzy"), ("subs-match-os-language", "yes"), ("subs-fallback", "yes"),
        ]
        for (name, value) in options { mpv.setOption(name, value) }
        guard mpv.initialize() else {
            mpv.destroy()
            return nil
        }

        mpv_observe_property(mpv.raw, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv.raw, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv.raw, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv.raw, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv.raw, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv.raw, 0, "track-list/count", MPV_FORMAT_NONE)
        mpv_observe_property(mpv.raw, 0, "aid", MPV_FORMAT_NONE)
        mpv_observe_property(mpv.raw, 0, "sid", MPV_FORMAT_NONE)

        // Unretained: shutdown() removes the callback before the player can go away.
        mpv_set_wakeup_callback(mpv.raw, { context in
            guard let context else { return }
            Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue().drainEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: Commands

    func load(_ url: URL, startAt seconds: Double) {
        mpv.setProperty("start", seconds > 5 ? "\(Int(seconds))" : "0")
        mpv.command(["loadfile", url.path])
    }

    func setPaused(_ paused: Bool) { mpv.setProperty("pause", paused ? "yes" : "no") }
    func togglePause() { mpv.command(["cycle", "pause"]) }
    func seek(to seconds: Double) { mpv.command(["seek", String(seconds), "absolute"]) }
    func seek(by seconds: Double) { mpv.command(["seek", String(seconds), "relative"]) }
    func selectAudio(_ id: Int) { mpv.setProperty("aid", String(id)) }
    func selectSubtitle(_ id: Int?) { mpv.setProperty("sid", id.map(String.init) ?? "no") }

    var currentPosition: Double { mpv.double("time-pos") ?? 0 }

    @MainActor
    func shutdown() {
        mpv_set_wakeup_callback(mpv.raw, nil, nil)
        eventQueue.sync { mpv.destroy() }
    }

    // MARK: Events

    private func drainEvents() {
        eventQueue.async { [self] in
            while let event = mpv_wait_event(mpv.raw, 0), event.pointee.event_id != MPV_EVENT_NONE {
                guard event.pointee.event_id == MPV_EVENT_PROPERTY_CHANGE,
                      let property = event.pointee.data?.assumingMemoryBound(to: mpv_event_property.self).pointee
                else { continue }
                handle(name: String(cString: property.name), format: property.format, data: property.data)
            }
        }
    }

    private func handle(name: String, format: mpv_format, data: UnsafeMutableRawPointer?) {
        switch (name, format) {
        case ("time-pos", MPV_FORMAT_DOUBLE), ("duration", MPV_FORMAT_DOUBLE):
            guard let value = data?.assumingMemoryBound(to: Double.self).pointee else { return }
            publish { state in
                if name == "time-pos" {
                    state.position = value
                    state.onPositionChange?(value)
                } else {
                    state.duration = value
                }
            }
        case ("pause", MPV_FORMAT_FLAG), ("paused-for-cache", MPV_FORMAT_FLAG), ("eof-reached", MPV_FORMAT_FLAG):
            guard let value = data?.assumingMemoryBound(to: Int32.self).pointee else { return }
            let flag = value != 0
            publish { state in
                switch name {
                case "pause": state.isPaused = flag
                case "paused-for-cache": state.isBuffering = flag
                default:
                    if flag && !state.reachedEnd { state.onEnd?() }
                    state.reachedEnd = flag
                }
            }
        case ("track-list/count", _), ("aid", _), ("sid", _):
            let (audio, subtitles) = readTracks()
            publish { state in
                state.audioTracks = audio
                state.subtitleTracks = subtitles
            }
        default:
            break
        }
    }

    private func readTracks() -> (audio: [MPVTrack], subtitles: [MPVTrack]) {
        var audio: [MPVTrack] = [], subtitles: [MPVTrack] = []
        for index in 0..<(mpv.int("track-list/count") ?? 0) {
            let prefix = "track-list/\(index)/"
            guard let type = mpv.string(prefix + "type"), let id = mpv.int(prefix + "id") else { continue }
            let language = mpv.string(prefix + "lang").map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            var parts = [mpv.string(prefix + "title"), language].compactMap { $0 }
            if type == "audio", let channels = VideoQuality.audioLabel(channels: mpv.int(prefix + "demux-channel-count")) {
                parts.append(channels)
            }
            let track = MPVTrack(
                id: id,
                label: parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · "),
                isSelected: mpv.flag(prefix + "selected") ?? false
            )
            if type == "audio" { audio.append(track) }
            if type == "sub" { subtitles.append(track) }
        }
        return (audio, subtitles)
    }

    private func publish(_ update: @escaping @MainActor @Sendable (MPVPlayerState) -> Void) {
        let state = self.state
        DispatchQueue.main.async {
            MainActor.assumeIsolated { update(state) }
        }
    }
}
