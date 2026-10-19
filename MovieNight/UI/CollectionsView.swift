import SwiftData
import SwiftUI

/// One card per folder (plus videos added on their own), each opening that folder's videos.
struct CollectionsView: View {
    @Query private var items: [MediaItem]

    var body: some View {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let groups = CollectionBuilder.build(items.map(\.browseEntry))
        ScrollView {
            if groups.isEmpty {
                ContentUnavailableView("No collections yet", systemImage: "rectangle.stack",
                                       description: Text("Each folder in your library becomes a collection."))
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth + 40, maximum: Theme.cardWidth + 120), spacing: 24, alignment: .top)],
                          alignment: .leading, spacing: 32) {
                    ForEach(groups) { group in
                        NavigationLink(value: CollectionRoute(id: group.id)) {
                            CollectionCard(group: group, cover: group.coverKey.flatMap { lookup[$0] })
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
        .navigationTitle("Collections")
        .navigationDestination(for: CollectionRoute.self) { route in
            CollectionDetailView(id: route.id)
        }
    }
}

/// Navigation value for a collection, so it doesn't collide with the String keys used for videos.
struct CollectionRoute: Hashable {
    var id: String
}

private struct CollectionCard: View {
    let group: CollectionGroup
    let cover: MediaItem?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // Two offset frames behind the cover make it read as a stack, not a single video.
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08))
                    .padding(.horizontal, 18).offset(y: -14)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.14))
                    .padding(.horizontal, 9).offset(y: -7)
                Group {
                    if let cover {
                        ArtworkView(item: cover, cornerRadius: 12)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1))
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(.top, 14)
            .scaleEffect(hovering ? 1.03 : 1)
            Text(group.title).font(.headline).lineLimit(1)
            Text(CollectionBuilder.subtitle(group)).font(.caption).foregroundStyle(.mutedText).lineLimit(1)
        }
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.title), \(CollectionBuilder.subtitle(group))")
        .accessibilityAddTraits(.isButton)
    }
}

struct CollectionDetailView: View {
    let id: String
    @Query private var items: [MediaItem]
    @AppStorage("collectionSortOldestFirst") private var oldestFirst = false

    var body: some View {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let group = CollectionBuilder.build(items.map(\.browseEntry)).first { $0.id == id }
        let keys = oldestFirst ? Array((group?.itemKeys ?? []).reversed()) : group?.itemKeys ?? []
        VideoGrid(items: keys.compactMap { lookup[$0] }) {
            ContentUnavailableView("This collection is empty", systemImage: "rectangle.stack")
        } header: {
            if let group {
                Text(CollectionBuilder.subtitle(group)).font(.subheadline).foregroundStyle(.mutedText)
            }
        }
        .navigationTitle(group?.title ?? "Collection")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Order", selection: $oldestFirst) {
                    Label("Newest First", systemImage: "arrow.down").tag(false)
                    Label("Oldest First", systemImage: "arrow.up").tag(true)
                }
                .pickerStyle(.menu)
            }
        }
    }
}
