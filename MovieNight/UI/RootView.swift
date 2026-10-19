import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var sources: [LibrarySource]
    @AppStorage(AccentChoice.key) private var accent = AccentChoice.silver
    @AppStorage(AccessibilityPreferences.highContrastKey) private var highContrast = false
    @Environment(\.colorSchemeContrast) private var systemContrast

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
        }
        .animation(.easeInOut(duration: 0.25), value: appModel.nowPlayingKey)
        .tint(accent.color)
        .environment(\.highContrast, highContrast || systemContrast == .increased)
    }
}

/// Home, Library, Collections and Settings: a sidebar on iPad and Mac (iPadOS 18 / macOS 15), tabs otherwise.
struct MainTabs: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        if #available(iOS 18, macOS 15, *) {
            TabView(selection: $model.tab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.systemImage, value: tab) { section(tab) }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $model.tab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
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
                case .library: LibraryView()
                case .collections: CollectionsView()
                case .settings: SettingsView(embedded: true)
                }
            }
            .navigationDestination(for: String.self) { key in DetailView(itemKey: key) }
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
                    case .folders: for url in urls { await store.addFolder(url) }
                    case .videos: await store.addFiles(urls)
                    }
                }
            }
            .onChange(of: kind) { _, new in
                if let new { lastKind = new }
            }
    }
}
