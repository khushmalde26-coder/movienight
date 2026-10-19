import Foundation

/// Which TMDB result is the user's file. Pure, so it's tested.
enum TitleMatcher {
    /// One TitleInfo per film (title and year from the file name) or per show.
    static func key(kind: ContentKind, title: String?, year: Int?, show: String?) -> String? {
        switch kind {
        case .film: title.map { "film|\(normalize($0))|\(year ?? 0)" }
        case .episode, .extra: show.map { "tv|\(normalize($0))" }
        case .homeVideo: nil
        }
    }

    /// "Schindler's List" and "Schindlers List", "Ocean’s Eleven" and "Oceans Eleven", "&" and "and" all compare equal.
    static func normalize(_ title: String) -> String {
        var text = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: #"['’`]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        let words = text.split(separator: " ").map(String.init)
        return (words.first == "the" ? Array(words.dropFirst()) : words).joined(separator: " ")
    }

    struct Candidate: Sendable, Hashable {
        var id: Int
        var titles: [String]
        var year: Int?
        var popularity: Double
    }

    /// The best candidate, or nil when nothing fits. An exact title match wins (a matching year breaks
    /// ties); otherwise TMDB's own top result, unless its year contradicts the file's by more than a year.
    static func best(_ candidates: [Candidate], title: String, year: Int?) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let wanted = normalize(title)
        let exact = candidates.filter { $0.titles.contains { normalize($0) == wanted } }
        if !exact.isEmpty {
            return exact.max { score($0, year: year) < score($1, year: year) }?.id
        }
        let top = candidates[0]
        if let year, let found = top.year, abs(found - year) > 1 { return nil }
        return top.id
    }

    private static func score(_ candidate: Candidate, year: Int?) -> Double {
        var score = min(candidate.popularity, 1000) / 1000
        if let year, let found = candidate.year {
            if found == year { score += 10 } else if abs(found - year) == 1 { score += 5 }
        }
        return score
    }
}
