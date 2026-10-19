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
                    if !source.isFile {
                        contentPicker(source)
                        TitleChekMenuItems(source: source)
                    }
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

    /// Change what a folder holds; its videos move between Films, TV and Home Videos right away.
    private func contentPicker(_ source: LibrarySource) -> some View {
        Picker("Contains", selection: Binding(get: { source.content }, set: { store.setContent($0, for: source) })) {
            ForEach(FolderContent.allCases) { Text($0.title).tag($0) }
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
            if scanning || (source.titleChek && store.titleChek.isRunning) { ProgressView().controlSize(.small) }
            if !source.isFile {
                Menu {
                    Picker("Contains", selection: Binding(get: { source.content }, set: { store.setContent($0, for: source) })) {
                        ForEach(FolderContent.allCases) { Text($0.title).tag($0) }
                    }
                    TitleChekMenuItems(source: source)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("What's in \(source.name)")
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(offline: Bool) -> String {
        switch (offline, source.isFile) {
        case (true, false): "Not connected. Videos stay in the library until it's back."
        case (true, true): "Not connected. It stays in the library until it's back."
        case (false, false): ["\(source.items.count) videos", source.content.title, source.titleChek && source.content != .homeVideos ? "TitleChek" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        case (false, true): source.items.first.map { Formatters.size($0.fileSize) } ?? "Video"
        }
    }
}

/// TitleChek for one folder: on or off, and a manual run.
private struct TitleChekMenuItems: View {
    let source: LibrarySource
    @Environment(LibraryStore.self) private var store

    var body: some View {
        if source.content != .homeVideos {
            Divider()
            Toggle(isOn: Binding(get: { source.titleChek }, set: { store.titleChek.setEnabled($0, for: source) })) {
                Label("TitleChek", systemImage: "checkmark.seal")
            }
            if source.titleChek {
                Button { Task { await store.titleChek.run(force: true) } } label: {
                    Label("Run TitleChek Now", systemImage: "arrow.clockwise")
                }
                .disabled(store.titleChek.isRunning)
            }
        }
    }
}
