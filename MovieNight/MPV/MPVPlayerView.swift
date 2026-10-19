import SwiftUI

/// Netflix-style controls over the mpv surface. AVKit files keep the system player instead.
struct MPVPlayerView: View {
    let session: MPVPlaybackSession
    let title: String
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubPosition: Double?
    @FocusState private var focused: Bool

    private var state: MPVPlayerState { session.state }

    var body: some View {
        ZStack {
            MPVSurface(view: session.renderView).ignoresSafeArea()

            if state.isBuffering {
                ProgressView().controlSize(.large).tint(.white)
            }

            controls
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        }
        .contentShape(Rectangle())
        .onTapGesture { showControls(!controlsVisible) }
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase { showControls(true) }
        }
        #endif
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space) { session.player.togglePause(); showControls(true); return .handled }
        .onKeyPress(.leftArrow) { session.player.seek(by: -10); showControls(true); return .handled }
        .onKeyPress(.rightArrow) { session.player.seek(by: 10); showControls(true); return .handled }
        .onAppear {
            focused = true
            showControls(true)
        }
        .onChange(of: state.isPaused) { showControls(true) }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                scrubber

                HStack(spacing: 28) {
                    Button { session.player.seek(by: -10) } label: { Image(systemName: "gobackward.10") }
                    Button { session.player.togglePause() } label: {
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30))
                            .frame(width: 36)
                    }
                    Button { session.player.seek(by: 10) } label: { Image(systemName: "goforward.10") }

                    Spacer()

                    if state.audioTracks.count > 1 {
                        Menu {
                            ForEach(state.audioTracks) { track in
                                Button {
                                    session.player.selectAudio(track.id)
                                } label: {
                                    if track.isSelected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                                }
                            }
                        } label: { Image(systemName: "waveform") }
                        .menuIndicator(.hidden)
                    }
                    if !state.subtitleTracks.isEmpty {
                        Menu {
                            Button("Off") { session.player.selectSubtitle(nil) }
                            ForEach(state.subtitleTracks) { track in
                                Button {
                                    session.player.selectSubtitle(track.id)
                                } label: {
                                    if track.isSelected { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                                }
                            }
                        } label: { Image(systemName: "captions.bubble") }
                        .menuIndicator(.hidden)
                    }
                    #if os(macOS)
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    #endif
                }
                .font(.title2)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .padding(.bottom, 28)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
        }
        .foregroundStyle(.white)
    }

    private var scrubber: some View {
        let duration = max(state.duration, 1)
        let shown = scrubPosition ?? state.position
        return VStack(spacing: 6) {
            Slider(
                value: Binding(get: { min(shown, duration) }, set: { scrubPosition = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing, let target = scrubPosition {
                        session.player.seek(to: target)
                        scrubPosition = nil
                    }
                    showControls(true)
                }
            )
            .tint(Theme.accent)
            HStack {
                Text(Formatters.clock(shown))
                Spacer()
                Text("-" + Formatters.clock(max(duration - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Controls hide after 3 seconds of playback, and stay up while paused.
    private func showControls(_ visible: Bool) {
        controlsVisible = visible
        hideTask?.cancel()
        guard visible else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !state.isPaused, scrubPosition == nil else { return }
            controlsVisible = false
        }
    }
}

#if os(macOS)
struct MPVSurface: NSViewRepresentable {
    let view: MPVRenderView
    func makeNSView(context: Context) -> MPVRenderView { view }
    func updateNSView(_ nsView: MPVRenderView, context: Context) {}
}
#else
struct MPVSurface: UIViewRepresentable {
    let view: MPVRenderView
    func makeUIView(context: Context) -> MPVRenderView { view }
    func updateUIView(_ uiView: MPVRenderView, context: Context) {}
}
#endif
