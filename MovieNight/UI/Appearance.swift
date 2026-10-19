import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The accent used for highlights, progress bars and chips. Applied app-wide with `.tint`.
enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case silver, crimson, ocean, amber, mint, violet
    var id: Self { self }
    static let key = "accentColor"

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .silver: Color(red: 0.961, green: 0.961, blue: 0.969)
        case .crimson: Color(red: 0.898, green: 0.141, blue: 0.188)
        case .ocean: Color(red: 0.278, green: 0.616, blue: 0.996)
        case .amber: Color(red: 0.992, green: 0.729, blue: 0.180)
        case .mint: Color(red: 0.388, green: 0.902, blue: 0.745)
        case .violet: Color(red: 0.690, green: 0.459, blue: 0.996)
        }
    }

    /// Text on a filled accent button: black on light accents, white on dark ones.
    var onAccent: Color { self == .crimson || self == .violet || self == .ocean ? .white : .black }
}

/// What sits behind the library. Gradients are drawn in code, so there are no images to license.
enum Wallpaper: String, CaseIterable, Identifiable, Sendable {
    case ink, dusk, ocean, ember, forest, aurora, photo
    var id: Self { self }
    static let key = "wallpaper"
    /// The built-in choices; `photo` is offered separately once one has been picked.
    static let builtIn: [Wallpaper] = [.ink, .dusk, .ocean, .ember, .forest, .aurora]

    var title: String {
        switch self {
        case .ink: "Ink"
        case .dusk: "Dusk"
        case .ocean: "Deep Sea"
        case .ember: "Ember"
        case .forest: "Forest"
        case .aurora: "Aurora"
        case .photo: "Your Photo"
        }
    }

    /// Two glows over ink: one from the top corner, one rising from the bottom.
    var glows: (Color, Color)? {
        switch self {
        case .ink, .photo: nil
        case .dusk: (Color(red: 0.42, green: 0.20, blue: 0.48), Color(red: 0.85, green: 0.38, blue: 0.30))
        case .ocean: (Color(red: 0.05, green: 0.28, blue: 0.45), Color(red: 0.02, green: 0.45, blue: 0.50))
        case .ember: (Color(red: 0.55, green: 0.12, blue: 0.08), Color(red: 0.80, green: 0.42, blue: 0.10))
        case .forest: (Color(red: 0.08, green: 0.32, blue: 0.20), Color(red: 0.30, green: 0.42, blue: 0.16))
        case .aurora: (Color(red: 0.10, green: 0.55, blue: 0.45), Color(red: 0.40, green: 0.22, blue: 0.70))
        }
    }

    // MARK: Custom photo

    static var photoURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Wallpaper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "wallpaper.jpg")
    }

    static var hasPhoto: Bool { FileManager.default.fileExists(atPath: photoURL.path) }

    /// Stores a picked photo, downscaled: it's shown blurred, so 1600px is plenty.
    static func savePhoto(_ data: Data) -> Bool {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func loadPhoto() -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// The page background everywhere: ink, a gradient, or the user's photo, kept dark enough for text.
struct WallpaperBackground: View {
    @AppStorage(Wallpaper.key) private var wallpaper = Wallpaper.ink
    /// Bumped when a new photo is saved, so the image reloads.
    @AppStorage("wallpaperRevision") private var revision = 0
    @State private var photo: CGImage?

    var body: some View {
        WallpaperSwatch(wallpaper: wallpaper, photo: photo)
            .ignoresSafeArea()
            .task(id: "\(wallpaper.rawValue)-\(revision)") {
                photo = wallpaper == .photo ? await Task.detached(priority: .utility) { Wallpaper.loadPhoto() }.value : nil
            }
    }
}

/// Draws one wallpaper at any size; also used for the thumbnails in Settings.
struct WallpaperSwatch: View {
    let wallpaper: Wallpaper
    var photo: CGImage?

    var body: some View {
        ZStack {
            Theme.background
            if let glows = wallpaper.glows {
                RadialGradient(colors: [glows.0.opacity(0.55), .clear], center: .topTrailing, startRadius: 0, endRadius: 900)
                RadialGradient(colors: [glows.1.opacity(0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 800)
            }
            if wallpaper == .photo, let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.55))
            }
        }
        .clipped()
    }
}

// MARK: Contrast

private struct HighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The app's High Contrast setting or the system's Increase Contrast, set once at the root.
    var highContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
}

/// Grey secondary text that turns near-white when contrast is raised.
struct MutedTextStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.highContrast ? Color.white.opacity(0.9) : Theme.secondaryText
    }
}

extension ShapeStyle where Self == MutedTextStyle {
    static var mutedText: MutedTextStyle { MutedTextStyle() }
}
