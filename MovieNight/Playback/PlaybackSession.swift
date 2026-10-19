import AVFoundation
import AVKit
import Observation
import SwiftUI

/// One play-through of one item on Apple's player: owns the AVPlayer and its layer, resumes,
/// records progress, and exposes tracks, subtitles and Picture in Picture to the shared controls.
/// MPVPlaybackSession is the equivalent for files AVFoundation can't open.
@MainActor
@Observable
final class PlaybackSession: PlayerEngine {
    let player: AVPlayer
    let state = PlayerState()
    let supportsAirPlayVideo = true
    @ObservationIgnored let layerView = PlayerLayerView()
    @ObservationIgnored private let item: MediaItem
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let playerItem: AVPlayerItem
    @ObservationIgnored private let sound: SoundProcessor
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSaved: Double = 0
    @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
    @ObservationIgnored private var pictureInPictureDelegate: PictureInPictureDelegate?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?

    // Tracks. Audio ids index `audioOptions`; subtitle ids below `sidecarBase` index the embedded
    // options, ids from `sidecarBase` index sidecar files.
    @ObservationIgnored private var audibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var audioOptions: [AVMediaSelectionOption] = []
    @ObservationIgnored private var legibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleOptions: [AVMediaSelectionOption] = []
    @ObservationIgnored private var sidecars: [[SubtitleCue]] = []
    @ObservationIgnored private let legible = LegibleCollector()
    @ObservationIgnored private var selectedSubtitle: Int?
    static let sidecarBase = 1000

    var surface: AnyView { AnyView(PlayerLayerSurface(view: layerView)) }

    /// `startAt` nil or 0 plays from the beginning.
    init(item: MediaItem, url: URL, store: LibraryStore, startAt: Double?) {
        self.item = item
        self.store = store
        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player.allowsExternalPlayback = true
        sound = SoundProcessor(settings: PlaybackPreferences.sound)
        layerView.playerLayer.player = player

        // Subtitles are drawn by SwiftUI so their size, colour and timing match mpv's.
        let output = AVPlayerItemLegibleOutput()
        output.suppressesPlayerRendering = true
        // Cues arrive 5 s early, which is what lets the subtitle delay go negative.
        output.advanceIntervalForDelegateInvocation = 5
        output.setDelegate(legible, queue: .main)
        playerItem.add(output)

        let start = startAt ?? 0
        lastSaved = start
        if start > 0 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        observe()
        player.play()

        // Dialogue boost, night mode and balance run in an audio tap on the file's sound track.
        let processor = sound
        let playerItem = playerItem
        Task {
            if let mix = await processor.audioMix(for: asset) { playerItem.audioMix = mix }
        }
        Task { await loadTracks(asset: asset, url: url) }
        setUpPictureInPicture()
    }

    // MARK: Observation

    private func observe() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        // KVO can fire on any thread; @Sendable keeps these closures off the main actor.
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { @Sendable [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.state.isPaused = status == .paused
                self?.state.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        })
        observations.append(playerItem.observe(\.duration, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            let seconds = item.duration.seconds
            Task { @MainActor in if seconds.isFinite { self?.state.duration = seconds } }
        })
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.reachedEnd = true
                self.store.saveProgress(self.item, seconds: self.item.duration ?? self.state.duration)
            }
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        state.position = seconds
        if state.reachedEnd, seconds < state.duration - 1 { state.reachedEnd = false }
        if abs(seconds - lastSaved) >= 5, seconds > 0 {
            lastSaved = seconds
            store.saveProgress(item, seconds: seconds)
        }
        updateSubtitleText()
    }

    // MARK: Tracks

    private func loadTracks(asset: AVURLAsset, url: URL) async {
        audibleGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        audioOptions = audibleGroup?.options ?? []
        subtitleOptions = (legibleGroup?.options ?? []).filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
        let files = SidecarSubtitles.find(for: url)
        sidecars = files.map(SidecarSubtitles.load)

        var subtitleTracks = subtitleOptions.enumerated().map { index, option in
            MediaTrack(id: index, label: option.displayName, language: option.extendedLanguageTag ?? option.locale?.identifier, isSelected: false)
        }
        for (index, file) in files.enumerated() where !sidecars[index].isEmpty {
            let (label, language) = SidecarSubtitles.describe(file)
            subtitleTracks.append(MediaTrack(id: Self.sidecarBase + index, label: label, language: language, isSelected: false))
        }
        state.subtitleTracks = subtitleTracks
        refreshAudioTracks()

        // Start the way the user last chose: their audio language, and subtitles in their language or off.
        if let audio = LanguagePreferences.match(LanguagePreferences.audio, in: state.audioTracks) { selectAudio(audio.id) }
        switch LanguagePreferences.subtitle {
        case LanguagePreferences.off?, nil: selectSubtitle(nil)
        case let language?: selectSubtitle(LanguagePreferences.match(language, in: state.subtitleTracks)?.id)
        }
    }

    private func refreshAudioTracks() {
        let selected = audibleGroup.flatMap { playerItem.currentMediaSelection.selectedMediaOption(in: $0) }
        state.audioTracks = audioOptions.count > 1 ? audioOptions.enumerated().map { index, option in
            MediaTrack(id: index, label: option.displayName, language: option.extendedLanguageTag ?? option.locale?.identifier,
                       isSelected: option == selected)
        } : []
    }

    func selectAudio(_ id: Int) {
        guard let audibleGroup, audioOptions.indices.contains(id) else { return }
        playerItem.select(audioOptions[id], in: audibleGroup)
        refreshAudioTracks()
    }

    func selectSubtitle(_ id: Int?) {
        selectedSubtitle = id
        if let legibleGroup {
            let option = id.flatMap { subtitleOptions.indices.contains($0) ? subtitleOptions[$0] : nil }
            playerItem.select(option, in: legibleGroup)
        }
        legible.reset()
        state.subtitleTracks = state.subtitleTracks.map { var track = $0; track.isSelected = track.id == id; return track }
        updateSubtitleText()
    }

    private func updateSubtitleText() {
        let time = state.position - state.subtitleDelay
        let text: String?
        switch selectedSubtitle {
        case nil: text = nil
        case let id? where id >= Self.sidecarBase:
            let index = id - Self.sidecarBase
            text = sidecars.indices.contains(index) ? SubtitleParser.cue(at: time, in: sidecars[index])?.text : nil
        default: text = legible.text(at: time)
        }
        if state.subtitleText != text { state.subtitleText = text }
    }

    // MARK: Controls

    func setPaused(_ paused: Bool) {
        if paused { player.pause() } else {
            if state.reachedEnd { seek(to: 0) }
            player.playImmediately(atRate: Float(state.rate))
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        state.position = seconds
        updateSubtitleText()
    }

    func setRate(_ rate: Double) {
        state.rate = rate
        player.defaultRate = Float(rate)
        if !state.isPaused { player.rate = Float(rate) }
    }

    func setVolume(_ volume: Double) {
        state.volume = volume
        player.volume = Float(volume)
    }

    func setSubtitleDelay(_ seconds: Double) {
        state.subtitleDelay = seconds
        updateSubtitleText()
    }

    /// Nothing to do here: SubtitleOverlay reads the style itself.
    func applySubtitleStyle(_ style: SubtitleStyle) {}

    func updateSound(_ settings: SoundSettings) {
        sound.update(settings)
    }

    // MARK: Picture in Picture and background

    private func setUpPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: layerView.playerLayer)
        else { return }
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        let delegate = PictureInPictureDelegate(state: state)
        controller.delegate = delegate
        pictureInPictureDelegate = delegate
        pictureInPicture = controller
        observations.append(controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { @Sendable [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.state.isPictureInPicturePossible = possible }
        })
    }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive {
            pictureInPicture.stopPictureInPicture()
        } else {
            pictureInPicture.startPictureInPicture()
        }
    }

    /// A player attached to a visible layer pauses in the background, so the layer lets go of it
    /// (unless Picture in Picture is showing it) and sound carries on.
    func setBackgrounded(_ backgrounded: Bool) {
        backgroundTask?.cancel()
        if backgrounded {
            // Leaving the app can start PiP automatically, a moment after the scene goes to the
            // background; detaching the layer before that would stop it. Wait, then check.
            backgroundTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !Task.isCancelled, self.pictureInPicture?.isPictureInPictureActive != true else { return }
                self.layerView.playerLayer.player = nil
            }
        } else {
            layerView.playerLayer.player = player
        }
    }

    /// Call when the player closes. Not done in deinit because deinit isn't main-actor isolated.
    func end() {
        if !state.reachedEnd {
            let seconds = player.currentTime().seconds
            if seconds.isFinite, seconds > 0 { store.saveProgress(item, seconds: seconds) }
        }
        pictureInPicture?.stopPictureInPicture()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observations.removeAll()
        layerView.playerLayer.player = nil
    }
}

/// Collects subtitle cues from AVPlayerItemLegibleOutput, which hands them over early and once each.
private final class LegibleCollector: NSObject, AVPlayerItemLegibleOutputPushDelegate, @unchecked Sendable {
    /// (start, text), text nil when the screen clears. Only touched on the main queue.
    private var cues: [(start: Double, text: String?)] = []

    func reset() { cues.removeAll() }

    func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime) {
        let text = strings.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let start = itemTime.seconds
        guard start.isFinite else { return }
        cues.removeAll { abs($0.start - start) < 0.001 }
        let index = cues.firstIndex { $0.start > start } ?? cues.endIndex
        cues.insert((start, text.isEmpty ? nil : text), at: index)
    }

    func text(at time: Double) -> String? {
        cues.last { $0.start <= time }?.text ?? nil
    }
}

private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate, @unchecked Sendable {
    private weak var state: PlayerState?

    init(state: PlayerState) { self.state = state }

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.state?.isPictureInPictureActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.state?.isPictureInPictureActive = false }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        // The player screen stays open underneath, so there's nothing to rebuild.
        completion(true)
    }
}

// MARK: Video layer

#if os(macOS)
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = playerLayer
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct PlayerLayerSurface: NSViewRepresentable {
    let view: PlayerLayerView
    func makeNSView(context: Context) -> PlayerLayerView { view }
    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}
}
#else
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct PlayerLayerSurface: UIViewRepresentable {
    let view: PlayerLayerView
    func makeUIView(context: Context) -> PlayerLayerView { view }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}
#endif
