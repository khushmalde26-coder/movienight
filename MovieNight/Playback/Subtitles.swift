import Foundation
import SwiftUI

struct SubtitleCue: Hashable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

/// SubRip (.srt) and WebVTT (.vtt), the sidecar formats people actually have.
enum SubtitleParser {
    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]),
                  let end = time(parts[1].split(separator: " ").first.map(String.init) ?? parts[1])
            else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n")
            let clean = stripTags(body)
            if !clean.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: clean)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:02,500", "01:02.500" or "1:02:03.5".
    static func time(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = value.split(separator: ":").map(String.init)
        guard (2...3).contains(fields.count), let seconds = Double(fields.last!) else { return nil }
        let rest = fields.dropLast().compactMap(Double.init)
        guard rest.count == fields.count - 1 else { return nil }
        return rest.reduce(0) { $0 * 60 + $1 } * 60 + seconds
    }

    /// Drops <i>, <font ...>, {\an8} and the like; keeps the words.
    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>|\{\\[^}]*\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The cue showing at `time`, by binary search.
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        var low = 0, high = cues.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard let index = found else { return nil }
        // Overlapping cues: the latest one that has started and not ended.
        for candidate in stride(from: index, through: max(index - 3, 0), by: -1) where cues[candidate].end > time {
            return cues[candidate]
        }
        return nil
    }
}

/// Subtitle files next to a video: Movie.srt, Movie.en.srt, Movie.English.vtt.
enum SidecarSubtitles {
    struct File: Hashable, Sendable {
        var url: URL
        /// The middle part of the name, if any: "en", "English", "forced".
        var tag: String?
    }

    static func find(for video: URL) -> [File] {
        let stem = video.deletingPathExtension().lastPathComponent.lowercased()
        let folder = video.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.compactMap { name in
            let lower = name.lowercased()
            guard lower.hasSuffix(".srt") || lower.hasSuffix(".vtt"), lower.hasPrefix(stem + ".") else { return nil }
            let middle = String(lower.dropFirst(stem.count + 1).dropLast(4)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return File(url: folder.appending(path: name), tag: middle.isEmpty ? nil : middle)
        }
        .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    static func load(_ file: File) -> [SubtitleCue] {
        guard let data = try? Data(contentsOf: file.url) else { return [] }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return SubtitleParser.parse(text)
    }

    /// A readable track name and a language code when the tag is one.
    static func describe(_ file: File) -> (label: String, language: String?) {
        guard let tag = file.tag else { return ("External", nil) }
        let code = Locale.LanguageCode(tag)
        if tag.count <= 3, let name = Locale.current.localizedString(forLanguageCode: tag) {
            return ("\(name) (external)", code.identifier)
        }
        return ("\(tag.capitalized) (external)", nil)
    }
}

/// How subtitles look. mpv gets these as properties; Apple's player subtitles are drawn by SwiftUI.
struct SubtitleStyle: Equatable, Sendable {
    enum Size: String, CaseIterable, Identifiable, Sendable {
        case small, medium, large, huge
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var scale: Double {
            switch self {
            case .small: 0.8
            case .medium: 1
            case .large: 1.3
            case .huge: 1.7
            }
        }
    }

    enum Background: String, CaseIterable, Identifiable, Sendable {
        case outline, box
        var id: Self { self }
        var title: String { self == .outline ? "Outline" : "Dark Box" }
    }

    enum TextColor: String, CaseIterable, Identifiable, Sendable {
        case white, yellow
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var color: Color { self == .white ? .white : Color(red: 1, green: 0.92, blue: 0.35) }
        var mpv: String { self == .white ? "#FFFFFF" : "#FFEB59" }
    }

    var size: Size = .medium
    var background: Background = .outline
    var color: TextColor = .white

    static let sizeKey = "subtitleSize"
    static let backgroundKey = "subtitleBackground"
    static let colorKey = "subtitleColor"

    static var current: SubtitleStyle {
        let defaults = UserDefaults.standard
        return SubtitleStyle(
            size: defaults.string(forKey: sizeKey).flatMap(Size.init(rawValue:)) ?? .medium,
            background: defaults.string(forKey: backgroundKey).flatMap(Background.init(rawValue:)) ?? .outline,
            color: defaults.string(forKey: colorKey).flatMap(TextColor.init(rawValue:)) ?? .white
        )
    }

    /// mpv properties. Styling is forced onto ASS subtitles too, so every file looks the same.
    var mpvProperties: [(String, String)] {
        var properties = [
            ("sub-scale", String(format: "%.2f", size.scale)),
            ("sub-color", color.mpv),
            ("sub-ass-override", "force"),
        ]
        switch background {
        case .outline:
            properties += [("sub-border-style", "outline-and-shadow"), ("sub-border-size", "3"), ("sub-back-color", "#00000000")]
        case .box:
            properties += [("sub-border-style", "background-box"), ("sub-back-color", "#B3000000")]
        }
        return properties
    }
}

/// Languages the user picked last time, so the next video starts the same way.
enum LanguagePreferences {
    static let subtitleKey = "preferredSubtitleLanguage"
    static let audioKey = "preferredAudioLanguage"
    /// Stored as the subtitle preference when the user turns subtitles off.
    static let off = "off"

    static var subtitle: String? { UserDefaults.standard.string(forKey: subtitleKey) }
    static var audio: String? { UserDefaults.standard.string(forKey: audioKey) }

    static func remember(subtitle track: MediaTrack?) {
        UserDefaults.standard.set(track.map { $0.language ?? "" } ?? off, forKey: subtitleKey)
    }

    static func remember(audio track: MediaTrack) {
        guard let language = track.language else { return }
        UserDefaults.standard.set(language, forKey: audioKey)
    }

    /// The track to pick for a remembered language: a matching code, or nil to leave the file's default.
    static func match(_ language: String?, in tracks: [MediaTrack]) -> MediaTrack? {
        guard let language, !language.isEmpty, language != off else { return nil }
        let wanted = Locale.LanguageCode(language)
        return tracks.first { track in
            guard let code = track.language else { return false }
            return code == language || Locale.LanguageCode(code) == wanted
                || Locale(identifier: code).language.languageCode == Locale(identifier: language).language.languageCode
        }
    }
}
