import Foundation
import FrameTrailCore

actor CatalogService {
    private let http: HTTPClient
    private let tokenProvider: @Sendable () throws -> String?
    static let tmdbTokenKey = "tmdb.read-token"

    init(http: HTTPClient = .shared, tokenProvider: @escaping @Sendable () throws -> String? = {
        try KeychainStore.string(for: CatalogService.tmdbTokenKey)
    }) {
        self.http = http
        self.tokenProvider = tokenProvider
    }

    func setTMDBReadToken(_ token: String?) throws {
        try KeychainStore.set(SourceText.validatedTMDBToken(token), for: Self.tmdbTokenKey)
    }

    func hasTMDBReadToken() throws -> Bool {
        try tokenProvider() != nil
    }

    func search(query: String) async throws -> [MediaTitle] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if let token = try tokenProvider() {
            let url = try HTTPClient.url("https://api.themoviedb.org/3/search/multi", query: [
                URLQueryItem(name: "query", value: String(query.prefix(200))),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "language", value: "en-US")
            ])
            let page = try await http.decode(TMDBPage.self, request: HTTPClient.request(url: url, bearer: token))
            return page.results.compactMap(\.mediaTitle)
        }
        async let series: Result<[MediaTitle], Error> = Result(catching: { try await self.searchSeries(query) })
        async let movies: Result<[MediaTitle], Error> = Result(catching: { try await self.searchMovies(query) })
        let results = await [series, movies]
        let titles = results.flatMap { (try? $0.get()) ?? [] }
        if titles.isEmpty, results.allSatisfy({ if case .failure = $0 { return true }; return false }) {
            if case .failure(let error) = results[0] { throw error }
        }
        return titles
    }

    func featured() async throws -> [MediaTitle] {
        if let token = try tokenProvider() {
            let url = try HTTPClient.url("https://api.themoviedb.org/3/trending/all/week", query: [.init(name: "language", value: "en-US")])
            let page = try await http.decode(TMDBPage.self, request: HTTPClient.request(url: url, bearer: token))
            return Array(page.results.compactMap(\.mediaTitle).prefix(20))
        }
        let client = http
        return try await withThrowingTaskGroup(of: (Int, MediaTitle?).self) { group in
            for (index, id) in [169, 82, 179, 431, 2993, 180].enumerated() {
                group.addTask {
                    let url = try HTTPClient.url("https://api.tvmaze.com/shows/\(id)")
                    let show = try? await client.decode(MazeShow.self, request: HTTPClient.request(url: url))
                    return (index, show?.mediaTitle)
                }
            }
            var titles: [(Int, MediaTitle)] = []
            for try await (index, title) in group {
                if let title { titles.append((index, title)) }
            }
            guard !titles.isEmpty else { throw ServiceError.invalidResponse }
            return titles.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func fetchEpisodes(for title: MediaTitle) async throws -> [Episode] {
        guard title.kind == .series else { return [] }
        if title.provider == "TMDB" {
            guard let token = try tokenProvider() else { throw ServiceError.missingTMDBToken }
            let url = try HTTPClient.url("https://api.themoviedb.org/3/tv/\(title.providerID)")
            let show = try await http.decode(TMDBShow.self, request: HTTPClient.request(url: url, bearer: token))
            var episodes: [Episode] = []
            // Fetch sequentially to stay within API rate limits and bound memory on long-running shows.
            for season in show.seasons where season.season_number > 0 {
                try Task.checkCancellation()
                let url = try HTTPClient.url("https://api.themoviedb.org/3/tv/\(title.providerID)/season/\(season.season_number)")
                let page = try await http.decode(TMDBSeason.self, request: HTTPClient.request(url: url, bearer: token))
                episodes.append(contentsOf: page.episodes.map { $0.episode(showID: title.providerID) })
            }
            return episodes
        }
        guard title.provider == "TVmaze" else { return [] }
        let url = try HTTPClient.url("https://api.tvmaze.com/shows/\(title.providerID)/episodes", query: [.init(name: "specials", value: "0")])
        return try await http.decode([MazeEpisode].self, request: HTTPClient.request(url: url)).compactMap(\.episode)
    }

    func episodes(for title: MediaTitle) async throws -> [Episode] { try await fetchEpisodes(for: title) }

    private func searchSeries(_ query: String) async throws -> [MediaTitle] {
        let url = try HTTPClient.url("https://api.tvmaze.com/search/shows", query: [.init(name: "q", value: String(query.prefix(200)))])
        return try await http.decode([MazeSearchResult].self, request: HTTPClient.request(url: url)).map { $0.show.mediaTitle }
    }

    private func searchMovies(_ query: String) async throws -> [MediaTitle] {
        let url = try HTTPClient.url("https://itunes.apple.com/search", query: [
            .init(name: "term", value: String(query.prefix(200))), .init(name: "entity", value: "movie"),
            .init(name: "limit", value: "25"), .init(name: "country", value: "us")
        ])
        return try await http.decode(ITunesPage.self, request: HTTPClient.request(url: url)).results.compactMap(\.mediaTitle)
    }
}

private struct MazeSearchResult: Decodable, Sendable { let show: MazeShow }
private struct MazeImage: Decodable, Sendable { let medium: URL? }
private struct MazeShow: Decodable, Sendable {
    let id: Int
    let name: String
    let premiered: String?
    let summary: String?
    let image: MazeImage?
    let url: URL?
    var mediaTitle: MediaTitle {
        MediaTitle(id: "tvmaze:\(id)", title: name, kind: .series, year: premiered.flatMap { Int($0.prefix(4)) },
                   overview: SourceText.plain(summary), posterURL: image?.medium, sourceURL: url, provider: "TVmaze", providerID: String(id))
    }
}
private struct MazeEpisode: Decodable, Sendable {
    let id: Int
    let season: Int
    let number: Int?
    let name: String
    let summary: String?
    let url: URL?
    var episode: Episode? {
        guard let number, season > 0, number > 0 else { return nil }
        return Episode(id: "tvmaze-episode:\(id)", season: season, number: number, name: name, summary: SourceText.plain(summary), sourceURL: url)
    }
}
private struct ITunesPage: Decodable, Sendable { let results: [ITunesMovie] }
private struct ITunesMovie: Decodable, Sendable {
    let trackId: Int?
    let trackName: String?
    let releaseDate: String?
    let longDescription: String?
    let trackViewUrl: URL?
    var mediaTitle: MediaTitle? {
        guard let trackId, let trackName else { return nil }
        return MediaTitle(id: "itunes:\(trackId)", title: trackName, kind: .movie,
                          year: releaseDate.flatMap { Int($0.prefix(4)) }, overview: longDescription ?? "",
                          sourceURL: trackViewUrl, provider: "Apple iTunes", providerID: String(trackId))
    }
}
struct TMDBPage: Decodable, Sendable {
    let results: [TMDBTitle]
    let total_pages: Int?
}
struct TMDBTitle: Decodable, Sendable {
    let id: Int
    let media_type: String?
    let title: String?
    let name: String?
    let original_title: String?
    let original_name: String?
    let overview: String?
    let release_date: String?
    let first_air_date: String?
    let poster_path: String?
    var mediaTitle: MediaTitle? {
        guard media_type == "movie" || media_type == "tv" else { return nil }
        return mediaTitle(as: media_type == "tv" ? .series : .movie)
    }
    func mediaTitle(as kind: MediaKind) -> MediaTitle? {
        guard let name = title ?? name else { return nil }
        let path = kind == .series ? "tv" : "movie"
        return MediaTitle(id: "tmdb:\(path):\(id)", title: name, originalTitle: original_title ?? original_name, kind: kind,
                          year: (release_date ?? first_air_date).flatMap { Int($0.prefix(4)) }, overview: overview ?? "",
                          posterURL: poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") },
                          sourceURL: URL(string: "https://www.themoviedb.org/\(path)/\(id)"), provider: "TMDB", providerID: String(id))
    }
}
private struct TMDBShow: Decodable, Sendable { let seasons: [TMDBSeasonSummary] }
private struct TMDBSeasonSummary: Decodable, Sendable { let season_number: Int }
private struct TMDBSeason: Decodable, Sendable { let episodes: [TMDBEpisode] }
private struct TMDBEpisode: Decodable, Sendable {
    let id: Int
    let season_number: Int
    let episode_number: Int
    let name: String
    let overview: String?
    func episode(showID: String) -> Episode {
        Episode(id: "tmdb-episode:\(id)", season: season_number, number: episode_number, name: name,
                summary: overview ?? "", sourceURL: URL(string: "https://www.themoviedb.org/tv/\(showID)/season/\(season_number)/episode/\(episode_number)"))
    }
}

private extension Result where Failure == Error {
    init(catching operation: () async throws -> Success) async {
        do { self = .success(try await operation()) } catch { self = .failure(error) }
    }
}
