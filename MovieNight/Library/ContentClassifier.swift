import Foundation

/// What a video is, which decides where it lives in the app.
enum ContentKind: String, Codable, Sendable, CaseIterable {
    case film, episode, homeVideo, extra
}

/// What the user says a folder holds, chosen when it's added. `auto` guesses per file.
enum FolderContent: String, CaseIterable, Identifiable, Sendable {
    case auto, filmsAndTV, homeVideos
    var id: Self { self }

    var title: String {
        switch self {
        case .auto: "Let Movie Night Decide"
        case .filmsAndTV: "Films & TV"
        case .homeVideos: "Home Videos"
        }
    }

    var summary: String {
        switch self {
        case .auto: "Camera clips become home videos, files named like S1E2 become TV episodes, the rest are films."
        case .filmsAndTV: "Loose files are films, folders of films are franchises, folders with S1E2-style names are TV shows."
        case .homeVideos: "Everything is a home video, arranged by when it was recorded."
        }
    }
}

struct ClassifierInput: Sendable, Hashable {
    var key: String
    /// Relative to the library folder, e.g. "Succession/Succession Season 1/Succession S1E1.mkv".
    var relativePath: String
    var fileName: String
    var duration: Double?
}

struct Classification: Sendable, Hashable {
    var kind: ContentKind
    /// Cleaned film title, or the show name for episodes and extras of a show.
    var title: String
    var show: String?
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    var year: Int?
    /// The folder a film sits in alongside related films (007, Dune, Kill Bill).
    var franchise: String?
}

/// Works out films, TV episodes, extras and home videos from names and folders alone (no network).
enum ContentClassifier {
    /// Clips shorter than this, with no episode number, count as home videos when guessing.
    static let homeVideoMaximum: Double = 8 * 60
    static let extraFolders: Set<String> = [
        "featurettes", "extras", "bonus", "bonus features", "behind the scenes", "deleted scenes",
        "interviews", "trailers", "shorts", "special features",
    ]

    static func classify(_ inputs: [ClassifierInput], folder: FolderContent) -> [String: Classification] {
        // A top-level folder with any episode in it is a TV show; everything else in it is an extra.
        var showFolders: Set<String> = []
        for input in inputs where parseEpisode(stem(input.fileName)) != nil {
            if let top = topFolder(input.relativePath) { showFolders.insert(top) }
        }

        var results: [String: Classification] = [:]
        for input in inputs {
            results[input.key] = classifyOne(input, folder: folder, showFolders: showFolders)
        }
        return results
    }

    private static func classifyOne(_ input: ClassifierInput, folder: FolderContent, showFolders: Set<String>) -> Classification {
        let name = stem(input.fileName)
        let components = input.relativePath.split(separator: "/").dropLast().map(String.init)
        let top = components.first
        let cleaned = cleanTitle(name)

        if folder == .homeVideos {
            return Classification(kind: .homeVideo, title: DisplayTitle.clean(name))
        }
        if components.contains(where: { extraFolders.contains($0.lowercased()) }) {
            let show = top.map { cleanTitle($0).title }
            return Classification(kind: .extra, title: cleaned.title, show: show)
        }
        if let parsed = parseEpisode(name) {
            let folderShow = top.map(cleanTitle)
            let show = folderShow?.title ?? parsed.show ?? cleaned.title
            let season = parsed.season ?? components.lazy.compactMap(seasonNumber).first
            return Classification(kind: .episode, title: show, show: show, season: season ?? 1, episode: parsed.episode,
                                  episodeTitle: parsed.title, year: folderShow?.year ?? parsed.year)
        }
        if let top, showFolders.contains(top) {
            return Classification(kind: .extra, title: cleaned.title, show: cleanTitle(top).title)
        }
        if folder == .auto, DisplayTitle.isCameraName(name) || (input.duration ?? .infinity) < homeVideoMaximum {
            return Classification(kind: .homeVideo, title: DisplayTitle.clean(name))
        }
        return Classification(kind: .film, title: cleaned.title, year: cleaned.year, franchise: top.map { cleanTitle($0).title })
    }

    // MARK: Parsing

    struct Episode: Equatable {
        var show: String?
        var season: Int?
        var episode: Int
        var title: String?
        var year: Int?
    }

    /// "Succession S1E10", "The White Lotus S01E01", "Invincible (2021) - S01E01 - It's About Time (1080p…)",
    /// "the.wire.s01e02.720p", "Fargo 2x03".
    static func parseEpisode(_ stem: String) -> Episode? {
        let text = stem.replacingOccurrences(of: #"[._]"#, with: " ", options: .regularExpression)
        let patterns = [#"(?i)\bS(\d{1,2})\s*E(\d{1,3})\b"#, #"(?i)\b(\d{1,2})x(\d{2,3})\b"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let seasonRange = Range(match.range(at: 1), in: text),
                  let episodeRange = Range(match.range(at: 2), in: text),
                  let whole = Range(match.range, in: text),
                  let episode = Int(text[episodeRange])
            else { continue }
            let before = cleanTitle(String(text[..<whole.lowerBound]))
            var after = String(text[whole.upperBound...])
            after = after.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:"))
            let title = cleanTitle(after).title
            return Episode(show: before.title.isEmpty ? nil : before.title, season: Int(text[seasonRange]), episode: episode,
                           title: title.isEmpty ? nil : title, year: before.year)
        }
        return nil
    }

    /// "Season 4", "The White Lotus Season 2", "S03" → the season number.
    static func seasonNumber(_ component: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b(?:season|series|s)\s*(\d{1,2})\b"#),
              let match = regex.firstMatch(in: component, range: NSRange(component.startIndex..., in: component)),
              let range = Range(match.range(at: 1), in: component)
        else { return nil }
        return Int(component[range])
    }

    static let releaseTags = #"(?i)\b(2160p|1080p|720p|480p|4k|uhd|hdr10?\+?|dv|dolby ?vision|web-?dl|web-?rip|webrip|bluray|blu-ray|brrip|bdrip|dvdrip|hdtv|remux|x26[45]|h ?26[45]|hevc|avc|aac|ac3|dts|ddp?5 ?1|atmos|10bit|proper|repack|extended|unrated|imax|yts|rarbg|sampa)\b"#

    /// "Interstellar " → "Interstellar"; "Dr No (1962)" → ("Dr No", 1962); "Heat.1995.1080p.BluRay" → ("Heat", 1995).
    static func cleanTitle(_ raw: String) -> (title: String, year: Int?) {
        var text = raw.replacingOccurrences(of: #"[._]"#, with: " ", options: .regularExpression)
        // Bracketed release info: [YTS], (1080p WEB-DL x265 SAMPA).
        text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\((?=[^)]*\#(releaseTags))[^)]*\)"#, with: " ", options: .regularExpression)
        var year: Int?
        let latestYear = Calendar(identifier: .gregorian).component(.year, from: .now) + 1
        if let regex = try? NSRegularExpression(pattern: #"[\(\s]((?:19|20)\d{2})(\))?(?=\s|$)"#),
           let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
           let range = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text),
           whole.lowerBound > text.startIndex, let found = Int(text[range]), found <= latestYear {
            // "(1962)" is always a year. A bare number only counts with release tags after it
            // ("Heat 1995 1080p"); otherwise it's part of the title ("Blade Runner 2049").
            let bracketed = match.range(at: 2).location != NSNotFound
            let rest = String(text[whole.upperBound...])
            if bracketed || rest.range(of: releaseTags, options: .regularExpression) != nil {
                year = found
                // Everything from the year on is release noise.
                text = String(text[..<whole.lowerBound])
            }
        }
        if let tag = text.range(of: releaseTags, options: .regularExpression) {
            text = String(text[..<tag.lowerBound])
        }
        let title = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:("))
        return (title.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : title, year)
    }

    private static func stem(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    private static func topFolder(_ relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }
}
