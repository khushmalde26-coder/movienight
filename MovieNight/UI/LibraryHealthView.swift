import SwiftData
import SwiftUI

/// Cleanup suggestions. Shows what might need attention; never deletes or moves anything.
struct LibraryHealthView: View {
    @Environment(LibraryStore.self) private var store
    @Query private var items: [MediaItem]

    var body: some View {
        let health = LibraryHealth.check(items.map(\.healthInput))
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        List {
            if health.count == 0 {
                ContentUnavailableView("Nothing to tidy up", systemImage: "checkmark.seal",
                                       description: Text("No duplicates, and every video can be played."))
            }
            if !health.duplicates.isEmpty {
                Section {
                    ForEach(health.duplicates, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.compactMap { lookup[$0] }) { HealthRow(item: $0) }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Possible Duplicates")
                } footer: {
                    Text("Same size and length in more than one place. Delete the copies you don't need in Files or Finder; Movie Night won't touch them.")
                }
            }
            if !health.unplayable.isEmpty {
                Section {
                    ForEach(health.unplayable.compactMap { lookup[$0] }) { item in
                        HStack {
                            HealthRow(item: item)
                            Spacer()
                            Button("Check Again") { Task { await store.recheck(item) } }
                                .buttonStyle(.bordered)
                                .disabled(!store.isAvailable(item))
                        }
                    }
                } header: {
                    Text("Can't Be Played")
                } footer: {
                    Text("These may be damaged, copy-protected, or still being copied.")
                }
            }
            if !health.notDownloaded.isEmpty {
                Section {
                    ForEach(health.notDownloaded.compactMap { lookup[$0] }) { item in
                        HStack {
                            HealthRow(item: item)
                            Spacer()
                            Button("Download") { store.download(item) }
                                .buttonStyle(.bordered)
                                .disabled(!store.isAvailable(item))
                        }
                    }
                } header: {
                    Text("Not Downloaded")
                } footer: {
                    Text("In iCloud but not on this device, so there's no artwork or length yet. They download when played.")
                }
            }
        }
        .navigationTitle("Suggestions")
    }
}

private struct HealthRow: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayTitle).font(.callout.weight(.medium)).lineLimit(1)
            Text([item.source?.name, item.source?.isFile == true ? nil : item.relativePath, Formatters.size(item.fileSize)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
