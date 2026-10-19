import AVFoundation
import SwiftData
import SwiftUI

@main
struct MovieNightApp: App {
    private let container: ModelContainer
    @State private var store: LibraryStore
    @State private var appModel = AppModel()

    init() {
        do {
            container = try ModelContainer(for: LibrarySource.self, MediaItem.self)
        } catch {
            fatalError("Couldn't open the library database: \(error)")
        }
        _store = State(initialValue: LibraryStore(context: container.mainContext))
        #if os(iOS)
        // Play sound even with the silent switch on, like any video app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(appModel)
                .preferredColorScheme(.dark)
                .task {
                    store.activateAll()
                    await store.rescanAll()
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
    }
}
