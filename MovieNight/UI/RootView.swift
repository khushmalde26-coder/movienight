import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var sources: [LibrarySource]
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.silver
    @AppStorage(AccessibilityPreferences.highContrastKey) private var highContrast = false
    @Environment(\.colorSchemeContrast) private var systemContrast
    /// The startup animation, shown once each time the app launches (not when it returns from the background).
    @State private var showingStartup = !StartupPreferences.skip

    var body: some View {
        ZStack {
            WallpaperBackground()

            if sources.isEmpty {
                WelcomeView()
            } else {
                MainTabs()
            }

            if let key = appModel.nowPlayingKey {
                PlayerView(itemKey: key)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if showingStartup {
                StartupView {
                    withAnimation(.easeInOut(duration: 0.5)) { showingStartup = false }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appModel.nowPlayingKey)
        .tint(accent.color)
        .environment(\.highContrast, highContrast || systemContrast == .increased)
    }
}

/// Home, Library, Collections and Settings: a sidebar on iPad and Mac (iPadOS 18 / macOS 15), tabs otherwise.
struct MainTabs: View {
    @Environment(AppModel.self) private var appModel
    @Query private var items: [MediaItem]

    /// Films, TV Shows and Home Videos only appear when the library has some.
    private var tabs: [AppTab] {
        let kinds = Set(items.map(\.kind))
        return AppTab.allCases.filter { tab in
            switch tab {
            case .films: kinds.contains(.film)
            case .tvShows: kinds.contains(.episode)
            case .homeVideos: kinds.contains(.homeVideo)
            default: true
            }
        }
    }

    var body: some View {
        @Bindable var model = appModel
        let tabs = tabs
        if #available(iOS 18, macOS 15, *) {
            TabView(selection: $model.tab) {
                ForEach(tabs, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.systemImage, value: tab) { section(tab) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $model.tab) {
                ForEach(tabs, id: \.self) { tab in
                    section(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
        }
    }

    /// Each section keeps its own navigation, so going back in Library doesn't reset Home.
    private func section(_ tab: AppTab) -> some View {
        NavigationStack {
            Group {
                switch tab {
                case .home: HomeView()
                case .films: FilmsView()
                case .tvShows: TVShowsView()
                case .homeVideos: HomeVideosView()
                case .library: LibraryView()
                case .collections: CollectionsView()
                case .settings: SettingsView(embedded: true)
                }
            }
            .navigationDestination(for: String.self) { key in DetailView(itemKey: key) }
            .navigationDestination(for: ShowRoute.self) { route in ShowDetailView(name: route.name) }
        }
    }
}

struct WelcomeView: View {
    @Environment(LibraryStore.self) private var store
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.silver
    @State private var importing: LibraryImport?

    var body: some View {
        VStack(spacing: 20) {
            Image("LogoStacked")
                .resizable()
                .scaledToFit()
                .frame(width: 260)
                .accessibilityLabel("Movie Night")
            Text("Point it at the folders or videos you want to watch: on this device, in iCloud Drive, or on an external drive. Everything stays where it is.")
                .font(.title3)
                .foregroundStyle(.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button {
                    importing = .folders
                } label: {
                    Label("Add a Folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(accent.onAccent)
                Button {
                    importing = .videos
                } label: {
                    Label("Add Videos", systemImage: "film")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .libraryImporter($importing)
    }
}

/// What the system picker is choosing.
enum LibraryImport: Identifiable {
    case folders, videos
    var id: Self { self }
}

extension View {
    /// The system file picker, wired to LibraryStore. Set the binding to open it.
    /// One importer per view: SwiftUI only honours one `fileImporter` on the same view.
    func libraryImporter(_ kind: Binding<LibraryImport?>) -> some View {
        modifier(LibraryImporter(kind: kind))
    }
}

private struct LibraryImporter: ViewModifier {
    @Binding var kind: LibraryImport?
    /// Kept after the picker closes, so the result is handled as what was asked for.
    @State private var lastKind: LibraryImport = .folders
    /// Folders just picked, waiting for "What's in this folder?".
    @State private var pendingFolders: [URL] = []
    @Environment(LibraryStore.self) private var store

    /// MKV, AVI and the rest have no system type that conforms to .movie, so name them by extension.
    private static let videoTypes: [UTType] = {
        var types: [UTType] = [.movie, .video, .audiovisualContent]
        for ext in LibraryScanner.videoExtensions.sorted() {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }()

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: Binding(get: { kind != nil }, set: { if !$0 { kind = nil } }),
                allowedContentTypes: (kind ?? lastKind) == .videos ? Self.videoTypes : [.folder],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                let picked = lastKind
                Task {
                    switch picked {
                    case .folders: pendingFolders = urls
                    case .videos: await store.addFiles(urls)
                    }
                }
            }
            .onChange(of: kind) { _, new in
                if let new { lastKind = new }
            }
            .sheet(isPresented: Binding(get: { !pendingFolders.isEmpty }, set: { if !$0 { pendingFolders = [] } })) {
                FolderSetupView(folders: pendingFolders) { content in
                    let folders = pendingFolders
                    pendingFolders = []
                    Task { for url in folders { await store.addFolder(url, content: content) } }
                }
            }
    }
}

/// "What's in this folder?", asked when a folder is added, so films, TV and home videos each go to the right place.
struct FolderSetupView: View {
    let folders: [URL]
    let onAdd: (FolderContent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content = FolderContent.auto

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([FolderContent.filmsAndTV, .homeVideos, .auto]) { option in
                        Button { content = option } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: content == option ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(content == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title).font(.headline)
                                    Text(option.summary).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(content == option ? .isSelected : [])
                    }
                } header: {
                    Text(folders.count == 1 ? "What's in \"\(folders[0].lastPathComponent)\"?" : "What's in these \(folders.count) folders?")
                } footer: {
                    Text("You can change this later in Folders and Videos.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { onAdd(content) } }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}

enum StartupPreferences {
    /// DEBUG builds can pass `-SkipStartup YES` (for screenshots and UI checks).
    static var skip: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "SkipStartup")
        #else
        false
        #endif
    }
}
