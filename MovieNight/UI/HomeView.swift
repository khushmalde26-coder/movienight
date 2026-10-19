import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var items: [MediaItem]
    @State private var showingSources = false
    @State private var showingSettings = false

    var body: some View {
        // Recomputed on change; cheap for libraries in the low thousands.
        // TODO: cache keyed on a library revision if it shows up in Instruments.
        let snapshots = items.map(\.snapshot)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let shelves = ShelfBuilder.build(snapshots)
        let hero = ShelfBuilder.heroKey(snapshots).flatMap { lookup[$0] }

        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    if let hero {
                        HeroBanner(item: hero)
                    } else if store.isScanning {
                        ProgressView("Building your library")
                            .frame(maxWidth: .infinity, minHeight: Theme.heroHeight)
                    } else {
                        ContentUnavailableView("No videos yet", systemImage: "film.stack",
                                               description: Text("Nothing you added contains a video yet."))
                            .frame(minHeight: Theme.heroHeight)
                    }

                    ForEach(shelves) { shelf in
                        ShelfRow(title: shelf.title, items: shelf.itemKeys.compactMap { lookup[$0] })
                    }
                }
                .padding(.bottom, 48)
                .id(Self.topID)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background { WallpaperBackground() }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    // Like a streaming app's logo: takes you back to the top of Home.
                    Button {
                        withAnimation(.easeInOut) { scroller.scrollTo(Self.topID, anchor: .top) }
                    } label: {
                        Image("LogoHorizontal")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Movie Night, back to top")
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
                        Label("Library", systemImage: "folder")
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSources) {
            SourcesView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

extension HomeView {
    fileprivate static let topID = "home-top"
}

struct HeroBanner: View {
    let item: MediaItem
    /// Off on the detail page, where "More Info" would push the same page again.
    var showsMoreInfo = true
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store
    @AppStorage(PlaybackPreferences.startFromBeginningKey) private var startFromBeginning = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(item: item, cornerRadius: 0, maxPixelSize: nil)
                .frame(height: Theme.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                // Fade the artwork itself out, so it melts into whatever wallpaper is behind it.
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: 12) {
                if !item.collection.isEmpty {
                    Text(item.collection.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.tint)
                }
                Text(item.displayTitle)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(2)
                MetadataLine(item: item)
                HStack(spacing: 12) {
                    PlayButton(item: item)
                    if item.resumePosition(startFromBeginning: startFromBeginning) != nil {
                        // Smart resume: continuing is the big button, starting over is right beside it.
                        Button {
                            appModel.play(item, from: 0)
                        } label: {
                            Label("Start Over", systemImage: "arrow.counterclockwise")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.isAvailable(item))
                    }
                    if showsMoreInfo {
                        NavigationLink(value: item.key) {
                            Label("More Info", systemImage: "info.circle")
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
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
            .foregroundStyle(.tint.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.tint.opacity(0.5), lineWidth: 1))
    }
}

struct PlayButton: View {
    let item: MediaItem
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store
    @AppStorage(PlaybackPreferences.startFromBeginningKey) private var startFromBeginning = false

    var body: some View {
        let resume = item.resumePosition(startFromBeginning: startFromBeginning)
        Button {
            appModel.play(item)
        } label: {
            Label(resume.map { "Resume from \(Formatters.clock($0))" } ?? "Play", systemImage: "play.fill")
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
