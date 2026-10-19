import SwiftData
import SwiftUI

/// A banner and rows, like Home. Shared by the Films and Home Videos sections.
struct ShelfPage<Footer: View>: View {
    let hero: MediaItem?
    let shelves: [Shelf]
    let lookup: [String: MediaItem]
    let emptyTitle: String
    let emptySymbol: String
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if let hero {
                    HeroBanner(item: hero)
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: emptySymbol).frame(minHeight: Theme.heroHeight)
                }
                ForEach(shelves) { shelf in
                    ShelfRow(title: shelf.title, items: shelf.itemKeys.compactMap { lookup[$0] })
                }
                footer
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background { WallpaperBackground() }
        #if os(iOS)
        // A large title would sit on top of the banner.
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Films

struct FilmsView: View {
    @Query private var items: [MediaItem]
    @State private var showingAll = false

    var body: some View {
        let films = items.filter { $0.kind == .film }
        let lookup = Dictionary(uniqueKeysWithValues: films.map { ($0.key, $0) })
        let entries = films.map(\.browseEntry)
        let hero = HomeShelves.heroKey(entries, homeVideos: []).flatMap { lookup[$0] }
        ShelfPage(hero: hero, shelves: FilmShelves.build(entries), lookup: lookup, emptyTitle: "No films yet", emptySymbol: "film") {
            if !films.isEmpty {
                ShelfRow(title: "All Films", items: films.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending })
            }
        }
        .navigationTitle("Films")
    }
}

// MARK: - TV

struct ShowRoute: Hashable {
    var name: String
}

struct TVShowsView: View {
    @Query private var items: [MediaItem]

    var body: some View {
        #if DEBUG
        // `-OpenShow <name>` opens a show page directly, for screenshots.
        if let name = UserDefaults.standard.string(forKey: "OpenShow") {
            ShowDetailView(name: name)
        } else {
            showGrid
        }
        #else
        showGrid
        #endif
    }

    @ViewBuilder private var showGrid: some View {
        let shows = TVLibrary.shows(items.map(\.browseEntry))
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        ScrollView {
            if shows.isEmpty {
                ContentUnavailableView("No TV shows yet", systemImage: "tv",
                                       description: Text("Files named like \"Show S1E2\" become TV shows."))
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth + 40, maximum: Theme.cardWidth + 120), spacing: 24, alignment: .top)],
                          alignment: .leading, spacing: 32) {
                    ForEach(shows) { show in
                        NavigationLink(value: ShowRoute(name: show.name)) {
                            ShowCard(show: show, cover: (show.nextKey ?? show.episodeKeys.first).flatMap { lookup[$0] }, lookup: lookup)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 20)
            }
        }
        .scrollIndicators(.hidden)
        .background { WallpaperBackground() }
        .navigationTitle("TV Shows")
    }
}

private struct ShowCard: View {
    let show: TVShowSummary
    let cover: MediaItem?
    let lookup: [String: MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let cover { ArtworkView(item: cover, cornerRadius: 12) } else { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            Text(show.name).font(.headline).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.mutedText).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(show.name), \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        let seasons = show.seasons.count == 1 ? "1 season" : "\(show.seasons.count) seasons"
        var parts = [seasons, show.episodeKeys.count == 1 ? "1 episode" : "\(show.episodeKeys.count) episodes"]
        if show.lastPlayedAt != nil, let next = show.nextKey.flatMap({ lookup[$0] }), let label = next.episodeNumber {
            parts.append("Next: S\(next.season ?? 1) E\(label)")
        }
        return parts.joined(separator: " · ")
    }
}

/// One show: play what's next, pick a season, and its episodes in order with progress.
struct ShowDetailView: View {
    let name: String
    @Query private var items: [MediaItem]
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store
    @State private var season: Int?

    var body: some View {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let show = TVLibrary.shows(items.map(\.browseEntry)).first { $0.name == name }
        let episodes = (show?.episodeKeys ?? []).compactMap { lookup[$0] }
        let next = show?.nextKey.flatMap { lookup[$0] }
        let selected = season ?? next?.season ?? show?.seasons.first ?? 1
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let banner = next ?? episodes.first {
                    ZStack(alignment: .bottomLeading) {
                        ArtworkView(item: banner, cornerRadius: 0, maxPixelSize: nil)
                            .frame(height: Theme.heroHeight * 0.8).frame(maxWidth: .infinity).clipped()
                            .mask { LinearGradient(stops: [.init(color: .black, location: 0.4), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(name).font(.largeTitle.bold())
                            if let next, store.isAvailable(next) {
                                Button { appModel.play(next) } label: {
                                    Label(playLabel(next, show: show), systemImage: "play.fill")
                                        .font(.headline).padding(.horizontal, 18).padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                            }
                        }
                        .padding(.horizontal, Theme.gutter).padding(.bottom, 20)
                    }
                }

                if let show, show.seasons.count > 1 {
                    Picker("Season", selection: Binding(get: { selected }, set: { season = $0 })) {
                        ForEach(show.seasons, id: \.self) { Text("Season \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 600)
                    .padding(.horizontal, Theme.gutter)
                }

                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(episodes.filter { ($0.season ?? 1) == selected }) { episode in
                        EpisodeRow(item: episode, isNext: episode.key == next?.key)
                    }
                }
                .padding(.horizontal, Theme.gutter)

                let extras = (show?.extraKeys ?? []).compactMap { lookup[$0] }
                if !extras.isEmpty {
                    ShelfRow(title: "Extras", items: extras)
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background { WallpaperBackground() }
        .navigationTitle(name)
        #if os(iOS)
        // The name is already in the banner.
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func playLabel(_ next: MediaItem, show: TVShowSummary?) -> String {
        let number = "S\(next.season ?? 1) E\(next.episodeNumber ?? 1)"
        if next.resumePosition() != nil { return "Resume \(number)" }
        return show?.lastPlayedAt == nil ? "Play \(number)" : "Next: \(number)"
    }
}

private struct EpisodeRow: View {
    let item: MediaItem
    let isNext: Bool
    @Environment(AppModel.self) private var appModel
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Button { appModel.play(item) } label: {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(item: item, cornerRadius: 8)
                    .frame(width: 200, height: 112)
                    .overlay(alignment: .bottom) {
                        if item.progressFraction > 0.02 && !item.isFinished { ProgressBar(fraction: item.progressFraction).padding(8) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.isFinished { Badge(text: "Watched", systemImage: "checkmark") }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(item.episodeNumber ?? 0). \(item.episodeTitle ?? "Episode \(item.episodeNumber ?? 0)")")
                            .font(.headline).lineLimit(2)
                        if isNext { QualityChip(text: "UP NEXT") }
                    }
                    Text([Formatters.duration(item.duration), Formatters.remaining(item.remainingSeconds)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.mutedText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.isAvailable(item))
        .contextMenu {
            Button { store.setWatched(item, !item.isFinished) } label: {
                Label(item.isFinished ? "Mark as Unwatched" : "Mark as Watched", systemImage: item.isFinished ? "circle" : "checkmark.circle")
            }
            NavigationLink(value: item.key) { Label("Details", systemImage: "info.circle") }
        }
        .accessibilityLabel("Episode \(item.episodeNumber ?? 0), \(item.episodeTitle ?? ""), \(Formatters.duration(item.duration) ?? "")\(item.isFinished ? ", watched" : "")")
    }
}

// MARK: - Home videos

/// Years, On This Day, folders: the rows built for camera footage, now only for camera footage.
struct HomeVideosView: View {
    @Query private var items: [MediaItem]

    var body: some View {
        let videos = items.filter { $0.kind == .homeVideo }
        let lookup = Dictionary(uniqueKeysWithValues: videos.map { ($0.key, $0) })
        let snapshots = videos.map(\.snapshot)
        let hero = ShelfBuilder.heroKey(snapshots).flatMap { lookup[$0] }
        ShelfPage(hero: hero, shelves: ShelfBuilder.build(snapshots), lookup: lookup, emptyTitle: "No home videos yet", emptySymbol: "video") {
            EmptyView()
        }
        .navigationTitle("Home Videos")
    }
}
