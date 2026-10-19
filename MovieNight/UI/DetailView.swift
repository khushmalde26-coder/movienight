import SwiftData
import SwiftUI

struct DetailView: View {
    let itemKey: String
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var siblings: [MediaItem]

    var body: some View {
        if let item = appModel.item(forKey: itemKey, in: modelContext) {
            content(item)
        } else {
            ContentUnavailableView("Video not found", systemImage: "film")
        }
    }

    private func content(_ item: MediaItem) -> some View {
        let related = siblings.filter {
            $0.key != item.key && $0.source?.id == item.source?.id && $0.collection == item.collection && !item.collection.isEmpty
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HeroBanner(item: item)

                VStack(alignment: .leading, spacing: 16) {
                    if item.isPlayable == false {
                        Label(PlaybackError.unsupportedFormat.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if !store.isAvailable(item) {
                        Label(PlaybackError.sourceOffline.localizedDescription, systemImage: "externaldrive.badge.xmark")
                            .foregroundStyle(.orange)
                    }

                    HStack(spacing: 12) {
                        if item.progressSeconds > 5 && !item.isFinished {
                            Button("Start Over") {
                                store.setWatched(item, false)
                                appModel.play(item)
                            }
                        }
                        Button(item.isFinished ? "Mark as Unwatched" : "Mark as Watched") {
                            store.setWatched(item, !item.isFinished)
                        }
                    }
                    .buttonStyle(.bordered)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        InfoRow(label: "File", value: item.fileName)
                        InfoRow(label: "Folder", value: item.collection.isEmpty ? nil : item.collection)
                        InfoRow(label: "Library", value: item.source?.name)
                        InfoRow(label: "Recorded", value: item.recordedAt?.formatted(date: .complete, time: .shortened))
                        InfoRow(label: "Size", value: Formatters.size(item.fileSize))
                    }
                    .font(.callout)
                }
                .padding(.horizontal, Theme.gutter)

                if !related.isEmpty {
                    ShelfRow(title: "More from \(item.collection)", items: related)
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(Theme.secondaryText)
                Text(value).textSelection(.enabled)
            }
        }
    }
}
