import AVKit
import SwiftData
import SwiftUI

/// Full-window player shown over the library. Apple's player handles MP4/MOV (PiP, AirPlay, HDR)
/// and mpv everything else, but both sit under the same controls, gestures and shortcuts.
struct PlayerView: View {
    let itemKey: String
    @Environment(LibraryStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine: (any PlayerEngine)?
    @State private var title = ""
    @State private var chapters: [Chapter] = []
    @State private var failure: String?
    @State private var toast: String?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubPosition: Double?
    @State private var gesture: GestureFeedback?
    @State private var showingSubtitleSettings = false
    @State private var nowPlaying = NowPlaying()
    @FocusState private var focused: Bool

    @AppStorage(PlaybackPreferences.dialogueBoostKey) private var dialogueBoost = false
    @AppStorage(PlaybackPreferences.nightModeKey) private var nightMode = false
    @AppStorage(PlaybackPreferences.balanceKey) private var balance = 0.0
    @AppStorage(SubtitleStyle.sizeKey) private var subtitleSize = SubtitleStyle.Size.medium
    @AppStorage(SubtitleStyle.backgroundKey) private var subtitleBackground = SubtitleStyle.Background.outline
    @AppStorage(SubtitleStyle.colorKey) private var subtitleColor = SubtitleStyle.TextColor.white
    @AppStorage(AccessibilityPreferences.largeControlsKey) private var largeControls = false
    /// The app's High Contrast setting or the system's Increase Contrast.
    @Environment(\.highContrast) private var highContrast

    private var subtitleStyle: SubtitleStyle {
        SubtitleStyle(size: subtitleSize, background: subtitleBackground, color: subtitleColor)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                engine.surface.ignoresSafeArea()
                if let text = engine.state.subtitleText {
                    SubtitleOverlay(text: text, style: subtitleStyle, raised: controlsVisible)
                }
                if engine.state.isBuffering {
                    ProgressView().controlSize(.large).tint(.white)
                }
                gestureLayer(engine)
                PlayerControls(
                    engine: engine, title: title, chapters: chapters,
                    largeControls: largeControls, highContrast: highContrast,
                    scrubPosition: $scrubPosition, showingSubtitleSettings: $showingSubtitleSettings,
                    dialogueBoost: $dialogueBoost, nightMode: $nightMode,
                    onClose: close, onSaveMoment: saveMoment, onInteraction: { showControls(true) }
                )
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
            } else {
                if let failure {
                    ContentUnavailableView("Can't play this video", systemImage: "exclamationmark.triangle", description: Text(failure))
                } else {
                    ProgressView("Loading").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button(action: close) { Image(systemName: "xmark").playerControl(large: largeControls) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }

            if let gesture { GestureHUD(feedback: gesture) }
            if let toast { ToastView(text: toast) }
        }
        .foregroundStyle(.white)
        #if os(iOS)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        #endif
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .task(id: itemKey) { await start() }
        .task(id: engine.map { ObjectIdentifier($0) }) { await keepNowPlayingCurrent() }
        .onChange(of: SoundSettings(dialogueBoost: dialogueBoost, nightMode: nightMode, balance: balance)) { _, sound in
            engine?.updateSound(sound)
        }
        .onChange(of: subtitleStyle) { _, style in engine?.applySubtitleStyle(style) }
        .onChange(of: scenePhase) { _, phase in engine?.setBackgrounded(phase == .background) }
        .onChange(of: engine?.state.isPaused) { showControls(true) }
        .onAppear { focused = true }
        .onDisappear {
            nowPlaying.stop()
            engine?.end()
        }
        .sheet(isPresented: $showingSubtitleSettings) {
            if let engine { SubtitleSettingsView(engine: engine) }
        }
    }

    // MARK: Start

    private func start() async {
        guard let item = appModel.item(forKey: itemKey, in: modelContext) else {
            failure = "This video is no longer in the library."
            return
        }
        if item.isPlayable == false {
            failure = PlaybackError.unsupportedFormat.localizedDescription
            return
        }
        do {
            let url = try await store.prepareForPlayback(item)
            // Closed while the file was downloading or being read: don't start a player nobody can see.
            try Task.checkCancellation()
            if item.isPlayable == false {
                failure = PlaybackError.unsupportedFormat.localizedDescription
                return
            }
            title = item.displayTitle
            chapters = item.chapters
            let startAt = appModel.startOverride ?? item.resumePosition()
            let started: (any PlayerEngine)?
            switch item.engine {
            case .mpv: started = MPVPlaybackSession(item: item, url: url, store: store, startAt: startAt)
            case .avKit, nil: started = PlaybackSession(item: item, url: url, store: store, startAt: startAt)
            }
            guard let started else {
                failure = "The extended player couldn't start."
                return
            }
            engine = started
            let thumbnail = item.thumbnailFile
            let artwork = await Task.detached(priority: .utility) { thumbnail.flatMap { ThumbnailService.load($0) } }.value
            nowPlaying.start(engine: started, artwork: artwork)
            showControls(true)
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }

    private func keepNowPlayingCurrent() async {
        guard let engine else { return }
        while !Task.isCancelled {
            nowPlaying.update(title: title, state: engine.state)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: Gestures

    /// Tap shows or hides the controls. Double-tap the left or right third to skip 10 s, the middle to
    /// pause. Drag up or down on the right for volume, on the left for brightness (iPad), and sideways to scrub.
    private func gestureLayer(_ engine: any PlayerEngine) -> some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2).onEnded { tap in
                        let third = proxy.size.width / 3
                        if tap.location.x < third {
                            engine.seek(by: -10); flash(.skip(-10))
                        } else if tap.location.x > third * 2 {
                            engine.seek(by: 10); flash(.skip(10))
                        } else {
                            engine.togglePause()
                        }
                    }
                    .exclusively(before: TapGesture().onEnded { showControls(!controlsVisible) })
                )
                .simultaneousGesture(dragGesture(engine, size: proxy.size))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        #if os(macOS)
        .onContinuousHover { phase in if case .active = phase { showControls(true) } }
        #endif
    }

    @State private var drag: DragKind?
    private enum DragKind { case scrub(from: Double), volume(from: Double), brightness(from: Double) }

    private func dragGesture(_ engine: any PlayerEngine, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if drag == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    if horizontal {
                        drag = .scrub(from: engine.state.position)
                    } else if value.startLocation.x < size.width / 2, let brightness = ScreenBrightness.value {
                        drag = .brightness(from: brightness)
                    } else {
                        drag = .volume(from: engine.state.volume)
                    }
                }
                switch drag {
                case .scrub(let from)?:
                    // A full swipe across the screen covers 90 s, or the whole of a short clip.
                    let span = min(90, max(engine.state.duration, 1))
                    let target = min(max(from + value.translation.width / size.width * span, 0), engine.state.duration)
                    scrubPosition = target
                    gesture = .scrub(target: target, duration: engine.state.duration)
                case .volume(let from)?:
                    let level = min(max(from - value.translation.height / (size.height * 0.6), 0), 1)
                    engine.setVolume(level)
                    gesture = .volume(level)
                case .brightness(let from)?:
                    let level = min(max(from - value.translation.height / (size.height * 0.6), 0), 1)
                    ScreenBrightness.value = level
                    gesture = .brightness(level)
                case nil: break
                }
            }
            .onEnded { _ in
                if case .scrub? = drag, let target = scrubPosition { engine.seek(to: target) }
                scrubPosition = nil
                drag = nil
                withAnimation(.easeOut(duration: 0.3)) { gesture = nil }
            }
    }

    private func flash(_ feedback: GestureFeedback) {
        gesture = feedback
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeOut(duration: 0.3)) { if gesture == feedback { gesture = nil } }
        }
    }

    // MARK: Keyboard

    /// Space play/pause, ←/→ 10 s (⇧ 30 s), ↑/↓ volume, M mute, C subtitles, B save moment,
    /// P Picture in Picture, [ and ] speed. Esc closes (the close button's shortcut).
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let engine else { return .ignored }
        let jump: Double = press.modifiers.contains(.shift) ? 30 : 10
        switch press.key {
        case .space: engine.togglePause()
        case .leftArrow: engine.seek(by: -jump); flash(.skip(-jump))
        case .rightArrow: engine.seek(by: jump); flash(.skip(jump))
        case .upArrow: engine.setVolume(min(engine.state.volume + 0.1, 1)); flash(.volume(engine.state.volume))
        case .downArrow: engine.setVolume(max(engine.state.volume - 0.1, 0)); flash(.volume(engine.state.volume))
        default:
            switch press.characters.lowercased() {
            case "m": engine.setVolume(engine.state.volume > 0 ? 0 : 1); flash(.volume(engine.state.volume))
            case "c": cycleSubtitles(engine)
            case "b": saveMoment()
            case "p": engine.togglePictureInPicture()
            case "]": engine.setRate(PlayerControls.nextSpeed(after: engine.state.rate, up: true)); show("Speed \(PlayerControls.speedLabel(engine.state.rate))")
            case "[": engine.setRate(PlayerControls.nextSpeed(after: engine.state.rate, up: false)); show("Speed \(PlayerControls.speedLabel(engine.state.rate))")
            default: return .ignored
            }
        }
        showControls(true)
        return .handled
    }

    private func cycleSubtitles(_ engine: any PlayerEngine) {
        let tracks = engine.state.subtitleTracks
        guard !tracks.isEmpty else { return show("No subtitles") }
        let current = tracks.firstIndex { $0.isSelected }
        let next: MediaTrack? = switch current {
        case nil: tracks.first
        case let index? where index + 1 < tracks.count: tracks[index + 1]
        default: nil
        }
        engine.selectSubtitle(next?.id)
        LanguagePreferences.remember(subtitle: next)
        show(next.map { "Subtitles: \($0.label)" } ?? "Subtitles off")
    }

    // MARK: Helpers

    private func saveMoment() {
        guard let engine else { return }
        let seconds = engine.state.position
        modelContext.insert(SavedMoment(itemKey: itemKey, seconds: seconds))
        try? modelContext.save()
        show("Saved \(Formatters.clock(seconds))")
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    /// Controls hide after 3 seconds of playback, and stay up while paused or scrubbing.
    private func showControls(_ visible: Bool) {
        controlsVisible = visible
        hideTask?.cancel()
        guard visible else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, engine?.state.isPaused == false, scrubPosition == nil, !showingSubtitleSettings else { return }
            controlsVisible = false
        }
    }

    private func close() {
        appModel.nowPlayingKey = nil
    }
}

// MARK: - Controls

struct PlayerControls: View {
    let engine: any PlayerEngine
    let title: String
    let chapters: [Chapter]
    let largeControls: Bool
    let highContrast: Bool
    @Binding var scrubPosition: Double?
    @Binding var showingSubtitleSettings: Bool
    @Binding var dialogueBoost: Bool
    @Binding var nightMode: Bool
    let onClose: () -> Void
    let onSaveMoment: () -> Void
    let onInteraction: () -> Void

    nonisolated static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    nonisolated static func speedLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }
    nonisolated static func nextSpeed(after rate: Double, up: Bool) -> Double {
        let index = speeds.firstIndex { $0 >= rate - 0.001 } ?? 2
        return speeds[min(max(index + (up ? 1 : -1), 0), speeds.count - 1)]
    }

    private var state: PlayerState { engine.state }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
                .background(LinearGradient(colors: [.black.opacity(highContrast ? 0.9 : 0.6), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            bottomBar
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .padding(.bottom, 24)
                .background(LinearGradient(colors: [.clear, .black.opacity(highContrast ? 0.95 : 0.8)], startPoint: .top, endPoint: .bottom))
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { Image(systemName: "xmark").playerControl(large: largeControls) }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            Text(title)
                .font(largeControls ? .title2.weight(.semibold) : .headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            RoutePicker()
                .frame(width: largeControls ? 54 : 46, height: largeControls ? 54 : 46)
                .accessibilityLabel(engine.supportsAirPlayVideo ? "AirPlay" : "AirPlay sound")
            if state.isPictureInPicturePossible {
                Button { engine.togglePictureInPicture() } label: {
                    Image(systemName: state.isPictureInPictureActive ? "pip.exit" : "pip.enter").playerControl(large: largeControls)
                }
                .accessibilityLabel("Picture in Picture")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            scrubber
            HStack(spacing: largeControls ? 36 : 28) {
                Button { engine.seek(by: -10); onInteraction() } label: { Image(systemName: "gobackward.10").transport(large: largeControls) }
                    .accessibilityLabel("Back 10 seconds")
                Button { engine.togglePause(); onInteraction() } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: largeControls ? 44 : 34))
                        .frame(width: largeControls ? 56 : 44, height: largeControls ? 56 : 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(state.isPaused ? "Play" : "Pause")
                Button { engine.seek(by: 10); onInteraction() } label: { Image(systemName: "goforward.10").transport(large: largeControls) }
                    .accessibilityLabel("Forward 10 seconds")
                Spacer()
                subtitlesMenu
                moreMenu
            }
        }
    }

    private var scrubber: some View {
        let duration = max(state.duration, 1)
        let shown = scrubPosition ?? state.position
        return VStack(spacing: 6) {
            Slider(
                value: Binding(get: { min(shown, duration) }, set: { scrubPosition = $0; onInteraction() }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing, let target = scrubPosition {
                        engine.seek(to: target)
                        scrubPosition = nil
                    }
                    onInteraction()
                }
            )
            .accessibilityLabel("Position")
            .accessibilityValue("\(Formatters.clock(shown)) of \(Formatters.clock(duration))")
            HStack {
                Text(Formatters.clock(shown))
                Spacer()
                Text("-" + Formatters.clock(max(duration - shown, 0)))
            }
            .font((largeControls ? Font.callout : .caption).monospacedDigit())
            .foregroundStyle(highContrast ? .white : Theme.secondaryText)
            .accessibilityHidden(true)
        }
    }

    private var subtitlesMenu: some View {
        Menu {
            Button {
                engine.selectSubtitle(nil)
                LanguagePreferences.remember(subtitle: nil)
            } label: {
                if state.subtitleTracks.allSatisfy({ !$0.isSelected }) { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(state.subtitleTracks) { track in
                Button {
                    engine.selectSubtitle(track.id)
                    LanguagePreferences.remember(subtitle: track)
                } label: {
                    if track.isSelected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                }
            }
            Divider()
            Button { showingSubtitleSettings = true } label: { Label("Timing and Style…", systemImage: "textformat.size") }
        } label: {
            Image(systemName: state.subtitleTracks.contains(where: \.isSelected) ? "captions.bubble.fill" : "captions.bubble")
                .transport(large: largeControls)
        }
        .accessibilityLabel("Subtitles")
    }

    private var moreMenu: some View {
        Menu {
            if state.audioTracks.count > 1 {
                Section("Audio") {
                    ForEach(state.audioTracks) { track in
                        Button {
                            engine.selectAudio(track.id)
                            LanguagePreferences.remember(audio: track)
                        } label: {
                            if track.isSelected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                        }
                    }
                }
            }
            Section("Sound") {
                Toggle("Boost Dialogue", isOn: $dialogueBoost)
                Toggle("Night Mode", isOn: $nightMode)
            }
            Picker("Speed", selection: Binding(get: { state.rate }, set: { engine.setRate($0) })) {
                ForEach(Self.speeds, id: \.self) { Text(Self.speedLabel($0)).tag($0) }
            }
            .pickerStyle(.menu)
            if !chapters.isEmpty {
                Menu("Chapters") {
                    ForEach(chapters, id: \.self) { chapter in
                        Button("\(chapter.title)  \(Formatters.clock(chapter.start))") { engine.seek(to: chapter.start) }
                    }
                }
            }
            Button(action: onSaveMoment) { Label("Save This Moment", systemImage: "bookmark") }
        } label: {
            Image(systemName: "ellipsis.circle").transport(large: largeControls)
        }
        .accessibilityLabel("More options")
    }
}

// MARK: - Subtitles on screen and their settings

struct SubtitleOverlay: View {
    let text: String
    let style: SubtitleStyle
    /// Lifted clear of the controls while they're showing.
    let raised: Bool
    @ScaledMetric(relativeTo: .title2) private var baseSize: CGFloat = 26

    var body: some View {
        Text(text)
            .font(.system(size: baseSize * style.size.scale, weight: .semibold))
            .foregroundStyle(style.color.color)
            .multilineTextAlignment(.center)
            .shadow(color: .black, radius: style.background == .outline ? 2 : 0)
            .shadow(color: .black, radius: style.background == .outline ? 4 : 0)
            .padding(.horizontal, style.background == .box ? 12 : 0)
            .padding(.vertical, style.background == .box ? 6 : 0)
            .background(style.background == .box ? Color.black.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 40)
            .padding(.bottom, raised ? 150 : 48)
            .animation(.easeInOut(duration: 0.2), value: raised)
            .allowsHitTesting(false)
    }
}

/// Timing and look of subtitles, changed while watching. Look and language are remembered.
struct SubtitleSettingsView: View {
    let engine: any PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SubtitleStyle.sizeKey) private var size = SubtitleStyle.Size.medium
    @AppStorage(SubtitleStyle.backgroundKey) private var background = SubtitleStyle.Background.outline
    @AppStorage(SubtitleStyle.colorKey) private var color = SubtitleStyle.TextColor.white

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Delay") {
                        HStack(spacing: 12) {
                            Button { nudge(-0.1) } label: { Image(systemName: "minus.circle.fill") }
                                .accessibilityLabel("Earlier")
                            Text(delayLabel).monospacedDigit().frame(minWidth: 70)
                            Button { nudge(0.1) } label: { Image(systemName: "plus.circle.fill") }
                                .accessibilityLabel("Later")
                        }
                        .font(.title3)
                        .buttonStyle(.plain)
                    }
                    if engine.state.subtitleDelay != 0 {
                        Button("Reset Timing") { engine.setSubtitleDelay(0) }
                    }
                } header: {
                    Text("Timing")
                } footer: {
                    Text("If words appear before people speak, make them later. Timing is for this video only.")
                }
                Section("Look") {
                    Picker("Size", selection: $size) { ForEach(SubtitleStyle.Size.allCases) { Text($0.title).tag($0) } }
                    Picker("Background", selection: $background) { ForEach(SubtitleStyle.Background.allCases) { Text($0.title).tag($0) } }
                    Picker("Colour", selection: $color) { ForEach(SubtitleStyle.TextColor.allCases) { Text($0.title).tag($0) } }
                    SubtitleOverlay(text: "The quick brown fox", style: SubtitleStyle(size: size, background: background, color: color), raised: false)
                        .padding(.bottom, -36)
                        .frame(height: 90)
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Subtitles")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 460)
        .presentationDetents([.medium, .large])
    }

    private var delayLabel: String {
        let delay = engine.state.subtitleDelay
        return delay == 0 ? "In sync" : String(format: "%+.1f s", delay)
    }

    private func nudge(_ amount: Double) {
        engine.setSubtitleDelay(((engine.state.subtitleDelay + amount) * 10).rounded() / 10)
    }
}

// MARK: - Feedback

enum GestureFeedback: Equatable {
    case skip(Double)
    case volume(Double)
    case brightness(Double)
    case scrub(target: Double, duration: Double)
}

private struct GestureHUD: View {
    let feedback: GestureFeedback

    var body: some View {
        Group {
            switch feedback {
            case .skip(let seconds):
                Label("\(seconds > 0 ? "+" : "")\(Int(seconds)) s", systemImage: seconds > 0 ? "goforward" : "gobackward")
            case .volume(let level):
                meter(icon: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level)
            case .brightness(let level):
                meter(icon: "sun.max.fill", level)
            case .scrub(let target, let duration):
                Text("\(Formatters.clock(target)) / \(Formatters.clock(duration))").monospacedDigit()
            }
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func meter(icon: String, _ value: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            ProgressView(value: value).frame(width: 140).tint(.white)
        }
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 80)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

private extension Image {
    func transport(large: Bool) -> some View {
        font(large ? .title.weight(.semibold) : .title2)
            .frame(width: large ? 52 : 40, height: large ? 52 : 40)
            .contentShape(Rectangle())
    }
}

extension Image {
    func playerControl(large: Bool) -> some View {
        font((large ? Font.title2 : .title3).weight(.semibold))
            .frame(width: large ? 30 : 22, height: large ? 30 : 22)
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
    }
}

// MARK: - Platform bits

/// The AirPlay button: video to an Apple TV for MP4/MOV, sound to speakers for everything.
#if os(macOS)
struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        return view
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#else
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

/// Screen brightness for the left-edge swipe. iPad and iPhone only; nil elsewhere.
@MainActor
enum ScreenBrightness {
    static var value: Double? {
        get {
            #if os(iOS)
            screen.map { Double($0.brightness) }
            #else
            nil
            #endif
        }
        set {
            #if os(iOS)
            if let newValue { screen?.brightness = CGFloat(newValue) }
            #endif
        }
    }

    #if os(iOS)
    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }
    #endif
}

/// Settings for people who need bigger targets or more contrast; the system's own settings
/// (Larger Text, Increase Contrast, Reduce Transparency) are honoured as well.
enum AccessibilityPreferences {
    static let largeControlsKey = "largePlayerControls"
    static let highContrastKey = "highContrast"
}
