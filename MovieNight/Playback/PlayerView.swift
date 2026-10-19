import AVKit
import SwiftData
import SwiftUI

/// Full-window player shown over the library. Files AVFoundation can open use the platform's
/// native player chrome (PiP, AirPlay, HDR for free); everything else goes through mpv.
struct PlayerView: View {
    let itemKey: String
    @Environment(LibraryStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var session: PlaybackSession?
    @State private var mpvSession: MPVPlaybackSession?
    @State private var title = ""
    @State private var chapters: [Chapter] = []
    @State private var failure: String?
    @State private var toast: String?
    @AppStorage(PlaybackPreferences.dialogueBoostKey) private var dialogueBoost = false
    @AppStorage(PlaybackPreferences.nightModeKey) private var nightMode = false
    @AppStorage(PlaybackPreferences.balanceKey) private var balance = 0.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let session {
                PlayerSurface(player: session.player).ignoresSafeArea()
            } else if let mpvSession {
                MPVPlayerView(session: mpvSession, title: title)
            } else if let failure {
                ContentUnavailableView("Can't play this video", systemImage: "exclamationmark.triangle", description: Text(failure))
                    .foregroundStyle(.white)
            } else {
                ProgressView("Loading").tint(.white).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            topBar.padding(20)

            if let toast {
                Text(toast)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .task(id: itemKey) { await start() }
        .onChange(of: SoundSettings(dialogueBoost: dialogueBoost, nightMode: nightMode, balance: balance)) { _, sound in
            session?.updateSound(sound)
            mpvSession?.updateSound(sound)
        }
        .onDisappear {
            session?.end()
            mpvSession?.end()
        }
    }

    private var isPlaying: Bool { session != nil || mpvSession != nil }

    /// Always reachable: close, plus bookmark, chapters and sound once a video is playing.
    private var topBar: some View {
        HStack(spacing: 10) {
            Button { close() } label: { Image(systemName: "xmark").circleControl() }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            if isPlaying {
                Button { saveMoment() } label: { Image(systemName: "bookmark").circleControl() }
                    .keyboardShortcut("b", modifiers: [])
                    .accessibilityLabel("Save this moment")
                if !chapters.isEmpty {
                    Menu {
                        ForEach(chapters, id: \.self) { chapter in
                            Button("\(chapter.title)  \(Formatters.clock(chapter.start))") { seek(to: chapter.start) }
                        }
                    } label: { Image(systemName: "list.bullet").circleControl() }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Chapters")
                }
                Menu {
                    Toggle("Boost Dialogue", isOn: $dialogueBoost)
                    Toggle("Night Mode", isOn: $nightMode)
                    Picker("Balance", selection: $balance) {
                        Text("Left").tag(-0.5)
                        Text("Centre").tag(0.0)
                        Text("Right").tag(0.5)
                    }
                } label: { Image(systemName: "speaker.wave.2").circleControl() }
                .menuIndicator(.hidden)
                .accessibilityLabel("Sound")
            }
        }
        .buttonStyle(.plain)
    }

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
            switch item.engine {
            case .mpv:
                guard let started = MPVPlaybackSession(item: item, url: url, store: store, startAt: startAt) else {
                    failure = "The extended player couldn't start."
                    return
                }
                mpvSession = started
            case .avKit, nil:
                session = PlaybackSession(item: item, url: url, store: store, startAt: startAt)
            }
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }

    private var currentTime: Double { session?.currentTime ?? mpvSession?.currentTime ?? 0 }

    private func seek(to seconds: Double) {
        session?.seek(to: seconds)
        mpvSession?.seek(to: seconds)
    }

    private func saveMoment() {
        let seconds = currentTime
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

    private func close() {
        appModel.nowPlayingKey = nil
    }
}

private extension Image {
    func circleControl() -> some View {
        font(.title3.weight(.semibold))
            .frame(width: 22, height: 22)
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
    }
}

#if os(macOS)
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#else
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
#endif
