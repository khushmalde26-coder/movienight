import SwiftUI

struct ShelfRow: View {
    let title: String
    let items: [MediaItem]
    /// Opened into a grid of every video in the row. Remembered per row title.
    @State private var expanded = false
    @SceneStorage("expandedShelves") private var expandedTitles = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.cardWidth, maximum: Theme.cardWidth + 60), spacing: 20, alignment: .top)],
                          alignment: .leading, spacing: 28) {
                    ForEach(items) { item in
                        NavigationLink(value: item.key) { PosterCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .transition(.opacity)
            } else {
                reel
            }
        }
        .onAppear { expanded = remembered.contains(title) }
    }

    /// The row's title, and the arrow that drops it down into a grid (or folds it back into a reel).
    private var header: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
            if items.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { setExpanded(!expanded) }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(items.count)").font(.subheadline.weight(.semibold).monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Show \(title) as a row" : "Show all \(items.count) in \(title) as a grid")
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var remembered: Set<String> {
        Set(expandedTitles.split(separator: "\n").map(String.init))
    }

    private func setExpanded(_ value: Bool) {
        expanded = value
        var titles = remembered
        if value { titles.insert(title) } else { titles.remove(title) }
        expandedTitles = titles.sorted().joined(separator: "\n")
    }

    private var reel: some View {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item.key) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8) // room for the hover scale
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
    }
}

struct PosterCard: View {
    let item: MediaItem
    @Environment(LibraryStore.self) private var store
    @Environment(\.highContrast) private var highContrast
    @State private var hovering = false

    var body: some View {
        let available = store.isAvailable(item)
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(item: item, cornerRadius: 10)
                .frame(width: Theme.cardWidth, height: Theme.cardWidth * 9 / 16)
                .overlay(alignment: .bottom) {
                    if item.progressFraction > 0.02 && !item.isFinished {
                        ProgressBar(fraction: item.progressFraction).padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Duration stamp, like a video thumbnail on any streaming site.
                    if item.progressFraction <= 0.02, let length = Formatters.clockLength(item.duration) {
                        Text(length)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !available {
                        Badge(text: "Offline", systemImage: "externaldrive.badge.xmark")
                    } else if item.isPlayable == false {
                        Badge(text: "Can't Open", systemImage: "exclamationmark.triangle")
                    } else if item.isFinished {
                        Badge(text: "Watched", systemImage: "checkmark")
                    }
                }
                .overlay {
                    if highContrast {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.6 : 0), radius: 16, y: 8)
                .scaleEffect(hovering ? 1.05 : 1)

            Text(item.displayTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let subtitle = Formatters.remaining(item.remainingSeconds) ?? subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.mutedText)
                }
                // Resolution is only worth a chip when it's notable; HD is the norm.
                ForEach((item.quality?.badges ?? []).filter { $0 != "HD" && $0 != "Vertical" }, id: \.self) {
                    QualityChip(text: $0, compact: true)
                }
            }
        }
        .frame(width: Theme.cardWidth, alignment: .leading)
        .opacity(available ? 1 : 0.45)
        // One stop for VoiceOver: title, when, how long, how far through, and anything notable.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(available: available))
        .accessibilityHint("Shows details")
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
    }
}

extension PosterCard {
    fileprivate func accessibilityDescription(available: Bool) -> String {
        var parts = [item.displayTitle]
        if let date = item.bestDate, !DisplayTitle.isCameraName((item.fileName as NSString).deletingPathExtension) {
            parts.append(date.formatted(date: .long, time: .omitted))
        }
        if let length = Formatters.duration(item.duration) { parts.append(length) }
        if item.isFinished {
            parts.append("Watched")
        } else if item.progressFraction > 0.02 {
            parts.append("\(Int((item.progressFraction * 100).rounded())) percent watched")
        }
        parts += (item.quality?.badges ?? []).filter { $0 != "HD" }.map(QualityChip.spoken)
        if !available { parts.append("Offline") } else if item.isPlayable == false { parts.append("Can't be opened") }
        return parts.joined(separator: ", ")
    }

    /// The length is already stamped on the artwork, so the line under the title says when or where.
    /// Camera-named clips are already titled by date, so they show their folder instead.
    fileprivate var subtitle: String? {
        let stem = (item.fileName as NSString).deletingPathExtension
        if DisplayTitle.isCameraName(stem), item.bestDate != nil {
            return item.collection.isEmpty ? nil : item.collection
        }
        return item.bestDate?.formatted(date: .abbreviated, time: .omitted)
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.tint).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}

struct Badge: View {
    let text: String
    let systemImage: String
    @Environment(\.highContrast) private var highContrast

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(highContrast ? AnyShapeStyle(.black) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .padding(8)
    }
}

/// Generated frame grab, or a tinted placeholder until it exists.
struct ArtworkView: View {
    let item: MediaItem
    var cornerRadius: CGFloat
    /// Decode size limit; nil for the full-size hero.
    var maxPixelSize: Int? = 640
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(placeholder)
            .overlay {
                if let image, image.height > image.width {
                    // Vertical phone video: fit it over a blurred fill instead of cropping it to a sliver.
                    ZStack {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 24)
                            .opacity(0.6)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: item.thumbnailFile) {
                guard let name = item.thumbnailFile else { image = nil; return }
                let maxPixelSize = maxPixelSize
                image = await Task.detached(priority: .utility) { ThumbnailService.load(name, maxPixelSize: maxPixelSize) }.value
            }
    }

    /// Stable per-item colour so placeholders don't all look identical.
    private var placeholder: LinearGradient {
        // String.hashValue is seeded per launch, so sum the bytes instead.
        let hue = Double(item.key.utf8.reduce(0) { ($0 &+ Int($1)) % 360 }) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.5, brightness: 0.35), Color(hue: hue, saturation: 0.6, brightness: 0.15)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
