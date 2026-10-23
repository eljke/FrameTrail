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

    func search(query: String, language: String = "en-US") async throws -> [MediaTitle] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        if let token = try tokenProvider() {
            let url = try HTTPClient.url("https://api.themoviedb.org/3/search/multi", query: [
                URLQueryItem(name: "query", value: String(query.prefix(200))),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "language", value: language)
            ])
            let page = try await http.decode(TMDBPage.self, request: HTTPClient.request(url: url, bearer: token))
            return page.results.compactMap(\.mediaTitle)
        }
        async let series: Result<[MediaTitle], Error> = Result(catching: { try await self.searchSeries(query) })
        async let movies: Result<[MediaTitle], Error> = Result(catching: { try await self.searchMovies(query, displayLanguage: language) })
        let results = await [series, movies]
        let titles = results.flatMap { (try? $0.get()) ?? [] }
        if titles.isEmpty, results.allSatisfy({ if case .failure = $0 { return true }; return false }) {
            if case .failure(let error) = results[0] { throw error }
        }
        return titles
    }

    func featured(language: String = "en-US") async throws -> [MediaTitle] {
        if let token = try tokenProvider() {
            let url = try HTTPClient.url("https://api.themoviedb.org/3/trending/all/week", query: [.init(name: "language", value: language)])
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

    func fetchEpisodes(for title: MediaTitle, language: String = "en-US") async throws -> [Episode] {
        guard title.kind == .series else { return [] }
        if title.provider == "TMDB" {
            guard let token = try tokenProvider() else { throw ServiceError.missingTMDBToken }
            let url = try HTTPClient.url("https://api.themoviedb.org/3/tv/\(title.providerID)", query: [.init(name: "language", value: "en-US")])
            let show = try await http.decode(TMDBShow.self, request: HTTPClient.request(url: url, bearer: token))
            var episodes: [Episode] = []
            // Fetch sequentially to stay within API rate limits and bound memory on long-running shows.
            for season in show.seasons where season.season_number > 0 {
                try Task.checkCancellation()
                let url = try HTTPClient.url("https://api.themoviedb.org/3/tv/\(title.providerID)/season/\(season.season_number)", query: [.init(name: "language", value: "en-US")])
                let page = try await http.decode(TMDBSeason.self, request: HTTPClient.request(url: url, bearer: token))
                if language == "en-US" {
                    episodes.append(contentsOf: page.episodes.map { $0.episode(showID: title.providerID) })
                } else {
                    let localizedURL = try HTTPClient.url("https://api.themoviedb.org/3/tv/\(title.providerID)/season/\(season.season_number)", query: [.init(name: "language", value: language)])
                    let localized = try await http.decode(TMDBSeason.self, request: HTTPClient.request(url: localizedURL, bearer: token))
                    let byID = Dictionary(localized.episodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    episodes.append(contentsOf: page.episodes.map { original in
                        var episode = (byID[original.id] ?? original).episode(showID: title.providerID)
                        episode.originalName = original.name
                        if episode.name.isEmpty { episode.name = original.name }
                        if episode.summary.isEmpty { episode.summary = original.overview ?? "" }
                        return episode
                    })
                }
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

    private func searchMovies(_ query: String, displayLanguage: String) async throws -> [MediaTitle] {
        let language = query.range(of: "[\\p{IsCyrillic}]", options: .regularExpression) == nil ? "en" : "ru"
        let url = try HTTPClient.url("https://www.wikidata.org/w/api.php", query: [
            .init(name: "action", value: "wbsearchentities"), .init(name: "search", value: String(query.prefix(200))),
            .init(name: "language", value: language), .init(name: "uselang", value: displayLanguage.hasPrefix("ru") ? "ru" : "en"),
            .init(name: "type", value: "item"), .init(name: "limit", value: "15"), .init(name: "format", value: "json")
        ])
        let page = try await http.decode(WikidataSearch.self, request: HTTPClient.request(url: url))
        guard !page.search.isEmpty else { return [] }
        let detailsURL = try HTTPClient.url("https://www.wikidata.org/w/api.php", query: [
            .init(name: "action", value: "wbgetentities"), .init(name: "ids", value: page.search.map(\.id).joined(separator: "|")),
            .init(name: "props", value: "claims|labels|descriptions"), .init(name: "languages", value: "en|ru"),
            .init(name: "format", value: "json")
        ])
        let details = try await http.decode(WikidataEntities.self, request: HTTPClient.request(url: detailsURL))
        return page.search.compactMap { hit in details.entities[hit.id]?.mediaTitle(for: hit, language: displayLanguage.hasPrefix("ru") ? "ru" : "en") }
    }

    func localizedTitle(_ title: MediaTitle, language: String) async throws -> MediaTitle {
        if title.provider == "TMDB", let token = try tokenProvider() {
            let path = title.kind == .series ? "tv" : "movie"
            let url = try HTTPClient.url("https://api.themoviedb.org/3/\(path)/\(title.providerID)", query: [.init(name: "language", value: language)])
            let localized = try await http.decode(TMDBTitle.self, request: HTTPClient.request(url: url, bearer: token))
            var result = localized.mediaTitle(as: title.kind) ?? title
            if result.overview.isEmpty { result.overview = title.overview }
            if result.posterURL == nil { result.posterURL = title.posterURL }
            return result
        }
        let code = language.hasPrefix("ru") ? "ru" : "en"
        if title.provider == "TVmaze", code == "en" {
            var result = title
            result.title = title.originalTitle ?? title.title
            return result
        }
        if title.provider == "TVmaze", code == "ru", Int(title.providerID) != nil {
            let query = "SELECT ?label WHERE { ?item <http://www.wikidata.org/prop/direct/P8600> \"\(title.providerID)\"; <http://www.w3.org/2000/01/rdf-schema#label> ?label. FILTER(LANG(?label)=\"ru\") } LIMIT 2"
            let url = try HTTPClient.url("https://query.wikidata.org/sparql", query: [.init(name: "query", value: query), .init(name: "format", value: "json")])
            let response = try await http.decode(WikidataLabels.self, request: HTTPClient.request(url: url))
            guard response.results.bindings.count == 1, let label = response.results.bindings.first?.label.value, !label.isEmpty else { return title }
            var result = title
            result.originalTitle = title.originalTitle ?? title.title
            result.title = label
            return result
        }
        if title.provider == "Wikidata" {
            let url = try HTTPClient.url("https://www.wikidata.org/w/api.php", query: [.init(name: "action", value: "wbgetentities"), .init(name: "ids", value: title.providerID), .init(name: "props", value: "labels|descriptions"), .init(name: "languages", value: "en|ru"), .init(name: "format", value: "json")])
            let response = try await http.decode(WikidataEntities.self, request: HTTPClient.request(url: url))
            var result = title
            result.title = response.entities[title.providerID]?.labels?[code]?.value ?? title.originalTitle ?? title.title
            result.overview = response.entities[title.providerID]?.descriptions?[code]?.value ?? title.overview
            return result
        }
        return title
    }
}

private struct WikidataLabels: Decodable, Sendable {
    let results: Results
    struct Results: Decodable, Sendable { let bindings: [Binding] }
    struct Binding: Decodable, Sendable { let label: Value }
    struct Value: Decodable, Sendable { let value: String }
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
private struct WikidataSearch: Decodable, Sendable {
    let search: [Hit]
    struct Hit: Decodable, Sendable { let id: String; let label: String? }
}
private struct WikidataEntities: Decodable, Sendable { let entities: [String: WikidataEntity] }
private struct WikidataText: Decodable, Sendable { let value: String }
private struct WikidataEntity: Decodable, Sendable {
    let labels: [String: WikidataText]?
    let descriptions: [String: WikidataText]?
    let claims: Claims?
    struct Claims: Decodable, Sendable { let P31: [Claim]?; let P577: [Claim]? }
    struct Claim: Decodable, Sendable {
        let rank: String?
        let mainsnak: Snak
    }
    struct Snak: Decodable, Sendable { let datavalue: DataValue? }
    struct DataValue: Decodable, Sendable { let value: Value }
    struct Value: Decodable, Sendable { let id: String?; let time: String? }

    func mediaTitle(for hit: WikidataSearch.Hit, language: String) -> MediaTitle? {
        let filmTypes: Set<String> = ["Q11424", "Q24869"]
        guard claims?.P31?.contains(where: { $0.rank != "deprecated" && $0.mainsnak.datavalue?.value.id.map(filmTypes.contains) == true }) == true,
              let name = labels?[language]?.value ?? hit.label ?? labels?["en"]?.value ?? labels?["ru"]?.value else { return nil }
        let date = claims?.P577?.first(where: { $0.rank != "deprecated" && $0.mainsnak.datavalue?.value.time != nil })?.mainsnak.datavalue?.value.time
        let year = date.flatMap { $0.hasPrefix("+") ? Int($0.dropFirst().prefix(4)) : nil }
        return MediaTitle(id: "wikidata:\(hit.id)", title: name, originalTitle: labels?["en"]?.value,
                          kind: .movie, year: year, overview: descriptions?[language]?.value ?? descriptions?["en"]?.value ?? "",
                          sourceURL: URL(string: "https://www.wikidata.org/wiki/\(hit.id)"), provider: "Wikidata", providerID: hit.id)
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
