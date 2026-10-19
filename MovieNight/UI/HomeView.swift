import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var items: [MediaItem]
    @State private var showingSources = false

    var body: some View {
        // Recomputed on change; cheap for libraries in the low thousands.
        // TODO: cache keyed on a library revision if it shows up in Instruments.
        let snapshots = items.map(\.snapshot)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let shelves = ShelfBuilder.build(snapshots)
        let hero = ShelfBuilder.heroKey(snapshots).flatMap { lookup[$0] }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if let hero {
                    HeroBanner(item: hero)
                } else if store.isScanning {
                    ProgressView("Building your library")
                        .frame(maxWidth: .infinity, minHeight: Theme.heroHeight)
                } else {
                    ContentUnavailableView("No videos yet", systemImage: "film.stack",
                                           description: Text("The folders you added don't contain any videos."))
                        .frame(minHeight: Theme.heroHeight)
                }

                ForEach(shelves) { shelf in
                    ShelfRow(title: shelf.title, items: shelf.itemKeys.compactMap { lookup[$0] })
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Image("LogoHorizontal")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                    .accessibilityLabel("Movie Night")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.rescanAll() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
                Button {
                    showingSources = true
                } label: {
                    Label("Folders", systemImage: "folder")
                }
            }
        }
        .sheet(isPresented: $showingSources) {
            SourcesView()
        }
    }
}

struct HeroBanner: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(item: item, cornerRadius: 0)
                .frame(height: Theme.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.35),
                            .init(color: Theme.background.opacity(0.7), location: 0.75),
                            .init(color: Theme.background, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 12) {
                if !item.collection.isEmpty {
                    Text(item.collection.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.accent)
                }
                Text(item.displayTitle)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(2)
                MetadataLine(item: item)
                HStack(spacing: 12) {
                    PlayButton(item: item)
                    NavigationLink(value: item.key) {
                        Label("More Info", systemImage: "info.circle")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }
}

/// Date · length · quality chips, as on a streaming service's title page.
struct MetadataLine: View {
    let item: MediaItem

    var body: some View {
        let length = Formatters.remaining(item.remainingSeconds) ?? Formatters.duration(item.duration)
        let parts = [Formatters.date(item.bestDate), length].compactMap { $0 }
        HStack(spacing: 10) {
            Text(parts.joined(separator: "  ·  "))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            ForEach(item.quality?.badges ?? [], id: \.self) { QualityChip(text: $0) }
        }
    }
}

/// Outlined label like "4K" or "HDR".
struct QualityChip: View {
    let text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(compact ? .system(size: 9, weight: .bold) : .caption2.weight(.bold))
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .foregroundStyle(Theme.accent.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
    }
}

struct PlayButton: View {
    let item: MediaItem
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let resuming = item.progressSeconds > 5 && !item.isFinished
        Button {
            appModel.play(item)
        } label: {
            Label(resuming ? "Resume" : "Play", systemImage: "play.fill")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .disabled(!store.isAvailable(item) || item.isPlayable == false)
    }
}
