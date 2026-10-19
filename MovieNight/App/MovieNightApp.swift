import AVFoundation
import Combine
import SwiftData
import SwiftUI

@main
struct MovieNightApp: App {
    private let container: ModelContainer
    @State private var store: LibraryStore
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try ModelContainer(for: LibrarySource.self, MediaItem.self, WatchRecord.self, SavedMoment.self)
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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refreshAvailability() } }
                }
                #if os(macOS)
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
                    Task { await store.refreshAvailability() }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
                    Task { await store.refreshAvailability() }
                }
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
    }
}
