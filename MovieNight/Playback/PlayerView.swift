import AVKit
import SwiftUI

/// Full-window player shown over the library. Uses the platform's native player chrome
/// so PiP, AirPlay, subtitles and HDR come for free.
struct PlayerView: View {
    let itemKey: String
    @Environment(LibraryStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var session: PlaybackSession?
        @State private var failure: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let session {
                PlayerSurface(player: session.player).ignoresSafeArea()
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
        .onDisappear { session?.end() }
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
            if item.isPlayable == false {
                failure = PlaybackError.unsupportedFormat.localizedDescription
                return
            }
            session = PlaybackSession(item: item, url: url, store: store)
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
