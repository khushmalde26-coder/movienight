import SwiftData
import SwiftUI

/// Manage the folders and individual videos the library is built from.
struct SourcesView: View {
    /// true when pushed inside Settings rather than shown as its own sheet.
    var embedded = false
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibrarySource.addedAt) private var sources: [LibrarySource]
    @Query private var items: [MediaItem]
    @State private var importing: LibraryImport?

    var body: some View {
        let folders = sources.filter { !$0.isFile }
        let videos = sources.filter(\.isFile)
        if embedded {
            list(folders: folders, videos: videos)
        } else {
            NavigationStack {
                list(folders: folders, videos: videos)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
    }

    private func list(folders: [LibrarySource], videos: [LibrarySource]) -> some View {
            List {
                Section {
                    NavigationLink {
                        LibraryHealthView()
                    } label: {
                        let count = LibraryHealth.check(items.map(\.healthInput)).count
                        LabeledContent {
                            Text(count == 0 ? "All good" : "\(count)")
                        } label: {
                            Label("Suggestions", systemImage: "sparkles")
                        }
                    }
                }
                if !folders.isEmpty {
                    Section("Folders") { rows(folders) }
                }
                if !videos.isEmpty {
                    Section("Videos") { rows(videos) }
                }
                if let error = store.lastError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
            .navigationTitle("Folders and Videos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { importing = .folders } label: { Label("Add Folder…", systemImage: "folder.badge.plus") }
                        Button { importing = .videos } label: { Label("Add Videos…", systemImage: "film") }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .libraryImporter($importing)
    }

    private func rows(_ sources: [LibrarySource]) -> some View {
        ForEach(sources) { source in
            SourceRow(source: source)
                .contextMenu {
                    Button("Rescan") { Task { await store.rescan(source) } }
                    Button("Remove from Library", role: .destructive) { store.remove(source) }
                }
                .swipeActions {
                    // The app-wide accent tint would otherwise repaint this (white on white with Silver).
                    Button(role: .destructive) { store.remove(source) } label: { Label("Remove", systemImage: "trash") }
                        .tint(.red)
                }
        }
    }
}

private struct SourceRow: View {
    let source: LibrarySource
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let offline = store.offlineSources.contains(source.id)
        let scanning = store.scanningSources.contains(source.id)
        HStack(spacing: 12) {
            Image(systemName: offline ? "externaldrive.badge.xmark" : source.isFile ? "film.fill" : "folder.fill")
                .foregroundStyle(offline ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.headline)
                Text(detail(offline: offline))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if scanning { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
    }

    private func detail(offline: Bool) -> String {
        switch (offline, source.isFile) {
        case (true, false): "Not connected. Videos stay in the library until it's back."
        case (true, true): "Not connected. It stays in the library until it's back."
        case (false, false): "\(source.items.count) videos"
        case (false, true): source.items.first.map { Formatters.size($0.fileSize) } ?? "Video"
        }
    }
}
