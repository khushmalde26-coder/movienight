import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var sources: [LibrarySource]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if sources.isEmpty {
                WelcomeView()
            } else {
                NavigationStack {
                    HomeView()
                        .navigationDestination(for: String.self) { key in
                            DetailView(itemKey: key)
                        }
                }
            }

            if let key = appModel.nowPlayingKey {
                PlayerView(itemKey: key)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appModel.nowPlayingKey)
    }
}

struct WelcomeView: View {
    @Environment(LibraryStore.self) private var store
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
                .foregroundStyle(Theme.secondaryText)
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
                .tint(Theme.accent)
                .foregroundStyle(.black)
                Button {
                    importing = .videos
                } label: {
                    Label("Add Videos", systemImage: "film")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
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
