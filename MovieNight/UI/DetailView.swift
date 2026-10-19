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

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 64) { detailsGrid(item); technicalGrid(item) }
                        VStack(alignment: .leading, spacing: 24) { detailsGrid(item); technicalGrid(item) }
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

extension DetailView {
    private func detailsGrid(_ item: MediaItem) -> some View {
        InfoSection(title: "Details") {
            InfoRow(label: "Length", value: Formatters.duration(item.duration))
            InfoRow(label: "Recorded", value: item.recordedAt?.formatted(date: .complete, time: .shortened))
            InfoRow(label: "Folder", value: item.collection.isEmpty ? nil : item.collection)
            InfoRow(label: "Library", value: item.source?.name)
            InfoRow(label: "File", value: item.fileName)
        }
    }

    private func technicalGrid(_ item: MediaItem) -> some View {
        let quality = item.quality
        let resolution = quality.map { "\($0.width) × \($0.height) (\($0.resolutionName))" }
        let frameRate = item.frameRate.map { String(format: $0.rounded() == $0 ? "%.0f fps" : "%.2f fps", $0) }
        let video = [item.videoCodec, item.isHDR && item.videoCodec != "Dolby Vision" ? "HDR" : nil, quality?.isVertical == true ? "Vertical" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        let player: String? = switch item.engine {
        case .avKit: "Built-in (AVKit)"
        case .mpv: "Extended (FFmpeg)"
        case nil: nil
        }
        return InfoSection(title: "Technical") {
            InfoRow(label: "Resolution", value: resolution)
            InfoRow(label: "Frame rate", value: frameRate)
            InfoRow(label: "Video", value: video.isEmpty ? nil : video)
            InfoRow(label: "Audio", value: VideoQuality.audioLabel(channels: item.audioChannels))
            InfoRow(label: "Bitrate", value: VideoQuality.bitrateLabel(fileSize: item.fileSize, duration: item.duration))
            InfoRow(label: "Size", value: Formatters.size(item.fileSize))
            InfoRow(label: "Player", value: player)
        }
    }
}

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) { content }
        }
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
