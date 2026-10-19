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
    @State private var picking = false

    var body: some View {
        VStack(spacing: 20) {
            Image("LogoStacked")
                .resizable()
                .scaledToFit()
                .frame(width: 260)
                .accessibilityLabel("Movie Night")
            Text("Point it at the folders where your videos live: this device, iCloud Drive, or an external drive. Everything stays where it is.")
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button {
                picking = true
            } label: {
                Label("Add a Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(.black)
        }
        .padding(40)
        .folderImporter(isPresented: $picking)
    }
}

extension View {
    /// The system folder picker, wired to LibraryStore.
    func folderImporter(isPresented: Binding<Bool>) -> some View {
        modifier(FolderImporter(isPresented: isPresented))
    }
}

private struct FolderImporter: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(LibraryStore.self) private var store

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls { await store.addFolder(url) }
            }
        }
    }
}
