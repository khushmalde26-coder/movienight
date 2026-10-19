import SwiftUI

/// Settings > TitleChek: the user's own TMDB token (kept in the Keychain), a check, and progress.
struct TitleChekSettings: View {
    @Environment(LibraryStore.self) private var store
    @State private var token = ""
    @State private var hasToken = TokenStore.hasToken
    @State private var status: Status?
    @State private var checking = false

    private enum Status { case accepted, rejected, unsaved }

    var body: some View {
        let service = store.titleChek
        Section {
            if hasToken {
                LabeledContent("TMDB Token") {
                    HStack(spacing: 8) {
                        if checking { ProgressView().controlSize(.small) }
                        switch status {
                        case .accepted: Label("Working", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .rejected: Label("Not accepted", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        default: Text("Saved").foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Check Token") { Task { await check() } }.disabled(checking)
                Button("Remove Token", role: .destructive) {
                    TokenStore.delete()
                    hasToken = false
                    status = nil
                }
            } else {
                SecureField("API Read Access Token", text: $token)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button("Save and Check") {
                    if TokenStore.save(token) {
                        token = ""
                        hasToken = true
                        Task { await check() }
                    } else {
                        status = .unsaved
                    }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if status == .unsaved {
                    Text("Couldn't save the token to the Keychain.").foregroundStyle(.red)
                }
                Link("Get a free token from TMDB", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
            }
            if service.isRunning {
                LabeledContent("Matching") {
                    if service.toCheck > 0 {
                        ProgressView(value: Double(service.checked), total: Double(service.toCheck))
                            .frame(maxWidth: 160)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            } else if hasToken {
                Button("Run TitleChek Now") { Task { await service.run() } }
            }
            if let error = service.lastError, hasToken {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
        } header: {
            Text("TitleChek")
        } footer: {
            Text("TitleChek looks up films and shows from folders where you turn it on, to fill in titles, years, artwork, genres, cast and episode names. Only titles and years are sent, never your files, and home videos never are. Turn it on per folder from the ⋯ in Folders and Videos.\n\nThis product uses the TMDB API but is not endorsed or certified by TMDB.")
        }
    }

    private func check() async {
        guard let token = TokenStore.token else { return }
        checking = true
        let accepted = await URLSessionTMDB(token: token).validate()
        checking = false
        status = accepted ? .accepted : .rejected
        if accepted { await store.titleChek.run() }
    }
}
