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
    @State private var failure: String?

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

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(20)
        }
        .task(id: itemKey) { await start() }
        .onDisappear {
            session?.end()
            mpvSession?.end()
        }
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
            switch item.engine {
            case .mpv:
                guard let started = MPVPlaybackSession(item: item, url: url, store: store,
                                                       fromStart: appModel.playsFromStart) else {
                    failure = "The extended player couldn't start."
                    return
                }
                mpvSession = started
            case .avKit, nil:
                session = PlaybackSession(item: item, url: url, store: store, fromStart: appModel.playsFromStart)
            }
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }

    private func close() {
        appModel.nowPlayingKey = nil
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
