import SwiftData
import SwiftUI

/// Every video, as a grid you can search, sort and filter. Sort and filter are remembered.
struct LibraryView: View {
    @Query private var items: [MediaItem]
    @AppStorage("librarySort") private var sort = LibrarySort.recorded
    @AppStorage("librarySortAscending") private var ascending = false
    @AppStorage("libraryFilter") private var filter = LibraryFilter.all
    @State private var search = ""
    @State private var showingSources = false

    var body: some View {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        let keys = LibraryQuery.apply(items.map(\.browseEntry), sort: sort, ascending: ascending, filter: filter, search: search)
        VideoGrid(items: keys.compactMap { lookup[$0] }) {
            if items.isEmpty {
                ContentUnavailableView("No videos yet", systemImage: "film.stack",
                                       description: Text("Add folders or videos in Settings."))
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView("Nothing here", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("No videos match \"\(filter.title)\"."))
            }
        } header: {
            Text(summary(count: keys.count))
                .font(.subheadline)
                .foregroundStyle(.mutedText)
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Titles, folders, years")
        .sheet(isPresented: $showingSources) { SourcesView() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSources = true
                } label: {
                    Label("Folders and Videos", systemImage: "folder")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Order", selection: $ascending) {
                        Text(sort == .title ? "A to Z" : "Newest or Longest First").tag(false)
                        Text(sort == .title ? "Z to A" : "Oldest or Shortest First").tag(true)
                    }
                    Divider()
                    Picker("Show", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Sort and Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }

    private func summary(count: Int) -> String {
        let videos = "\(count) video\(count == 1 ? "" : "s")"
        return filter == .all ? videos : "\(videos) · \(filter.title)"
    }
}

/// Poster cards in a grid that fills the width, used by Library and each collection.
struct VideoGrid<Empty: View, Header: View>: View {
    let items: [MediaItem]
    @ViewBuilder var empty: Empty
    @ViewBuilder var header: Header

    var body: some View {
        ScrollView {
            if items.isEmpty {
                empty.frame(maxWidth: .infinity, minHeight: 400)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth, maximum: Theme.cardWidth + 60), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(items) { item in
                            NavigationLink(value: item.key) { PosterCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 20)
            }
        }
        .scrollIndicators(.hidden)
        .background { WallpaperBackground() }
    }
}
