import SwiftData
import SwiftUI

struct DetailView: View {
    let itemKey: String
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var siblings: [MediaItem]
    @Query private var moments: [SavedMoment]

    init(itemKey: String) {
        self.itemKey = itemKey
        _moments = Query(filter: #Predicate<SavedMoment> { $0.itemKey == itemKey }, sort: \.seconds)
    }

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
                HeroBanner(item: item, showsMoreInfo: false)

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
                        Button(item.isFinished ? "Mark as Unwatched" : "Mark as Watched") {
                            store.setWatched(item, !item.isFinished)
                        }
                        if item.isInContinueWatching {
                            Button("Remove from Continue Watching") { store.removeFromContinueWatching(item) }
                        }
                    }
                    .buttonStyle(.bordered)

                    if !moments.isEmpty {
                        TimestampList(title: "Saved Moments", rows: moments.map { ("Saved \($0.createdAt.formatted(date: .abbreviated, time: .shortened))", $0.seconds) }) {
                            appModel.play(item, from: $0)
                        } onDelete: { index in
                            modelContext.delete(moments[index])
                            try? modelContext.save()
                        }
                    }
                    if !item.chapters.isEmpty {
                        TimestampList(title: "Chapters", rows: item.chapters.map { ($0.title, $0.start) }) {
                            appModel.play(item, from: $0)
                        }
                    }

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
        .background { WallpaperBackground() }
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
                Text(label).foregroundStyle(.mutedText)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

/// Tappable list of times on the detail page: saved moments or chapters.
private struct TimestampList: View {
    let title: String
    let rows: [(label: String, seconds: Double)]
    let onPlay: (Double) -> Void
    var onDelete: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Button { onPlay(row.seconds) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill").foregroundStyle(.tint)
                            Text(row.label).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(Formatters.clock(row.seconds))
                                .monospacedDigit()
                                .foregroundStyle(.mutedText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let onDelete {
                        Button { onDelete(index) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.mutedText)
                            .accessibilityLabel("Delete")
                    }
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}
