import SwiftData
import SwiftUI

/// Manage the folders the library is built from.
struct SourcesView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibrarySource.addedAt) private var sources: [LibrarySource]
    @State private var picking = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(sources) { source in
                    SourceRow(source: source)
                        .contextMenu {
                            Button("Rescan") { Task { await store.rescan(source) } }
                            Button("Remove from Library", role: .destructive) { store.remove(source) }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { store.remove(source) }
                        }
                }
                if let error = store.lastError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
            .navigationTitle("Folders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { picking = true } label: { Label("Add Folder", systemImage: "plus") }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .folderImporter(isPresented: $picking)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct SourceRow: View {
    let source: LibrarySource
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let offline = store.offlineSources.contains(source.id)
        let scanning = store.scanningSources.contains(source.id)
        HStack(spacing: 12) {
            Image(systemName: offline ? "externaldrive.badge.xmark" : "folder.fill")
                .foregroundStyle(offline ? .secondary : Theme.accent)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.headline)
                Text(offline ? "Not connected. Videos stay in the library until it's back." : "\(source.items.count) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if scanning { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
    }
}
