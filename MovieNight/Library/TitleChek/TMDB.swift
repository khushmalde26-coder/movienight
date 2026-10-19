import Foundation

/// The few TMDB API v3 endpoints TitleChek uses. Only titles and years go out; files never leave the device.
enum TMDB {
    struct SearchResults<Result: Decodable & Sendable>: Decodable, Sendable { var results: [Result] }

    struct MovieResult: Decodable, Sendable, Hashable {
        var id: Int
        var title: String
        var originalTitle: String?
        var releaseDate: String?
        var popularity: Double?
    }

    struct ShowResult: Decodable, Sendable, Hashable {
        var id: Int
        var name: String
        var originalName: String?
        var firstAirDate: String?
        var popularity: Double?
    }

    struct Named: Decodable, Sendable, Hashable { var name: String }
    struct CrewMember: Decodable, Sendable, Hashable { var name: String; var job: String? }
    struct Credits: Decodable, Sendable { var cast: [Named]?; var crew: [CrewMember]? }

    struct MovieDetails: Decodable, Sendable {
        var id: Int
        var title: String
        var releaseDate: String?
        var overview: String?
        var genres: [Named]?
        var posterPath: String?
        var backdropPath: String?
        var belongsToCollection: Named?
        var voteAverage: Double?
        var credits: Credits?
    }

    struct ShowDetails: Decodable, Sendable {
        var id: Int
        var name: String
        var firstAirDate: String?
        var overview: String?
        var genres: [Named]?
        var posterPath: String?
        var backdropPath: String?
        var createdBy: [Named]?
        var voteAverage: Double?
        var credits: Credits?
    }

    struct Season: Decodable, Sendable {
        struct Episode: Decodable, Sendable { var episodeNumber: Int; var name: String? }
        var episodes: [Episode]
    }

    static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// How requests reach TMDB. The live one uses URLSession; tests use canned replies.
protocol TMDBTransport: Sendable {
    func get(_ path: String, query: [String: String]) async throws -> Data
    func image(_ path: String, size: String) async throws -> Data
}

enum TitleChekError: LocalizedError {
    case noToken
    case rejected
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .noToken: "Add your TMDB token in Settings > TitleChek."
        case .rejected: "TMDB didn't accept the token. Check it in Settings > TitleChek."
        case .server(let code): "TMDB returned an error (\(code)). Try again later."
        }
    }
}

struct URLSessionTMDB: TMDBTransport {
    let token: String
    var session: URLSession = .shared

    func get(_ path: String, query: [String: String]) async throws -> Data {
        var components = URLComponents(string: "https://api.themoviedb.org/3/" + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TitleChekError.rejected }
        guard (200..<300).contains(status) else { throw TitleChekError.server(status) }
        return data
    }

    func image(_ path: String, size: String) async throws -> Data {
        let (data, response) = try await session.data(from: URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")!)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200 else { throw TitleChekError.server(0) }
        return data
    }

    /// true when TMDB accepts the token.
    func validate() async -> Bool {
        (try? await get("authentication", query: [:])) != nil
    }
}
