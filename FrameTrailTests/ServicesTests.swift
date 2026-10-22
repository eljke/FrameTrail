import XCTest
import FrameTrailCore
@testable import FrameTrail

final class ServicesTests: XCTestCase {
    override func tearDown() {
        ServiceURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testFallbackSearchCombinesRealProviderShapes() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.host == "api.tvmaze.com" {
                return .json("""
                [{"score":0.97,"show":{"id":82,"name":"Sample Show","url":"https://www.tvmaze.com/shows/82/sample","premiered":"2011-04-17","summary":"<p>A <b>family</b> story &amp; mystery.</p>","image":null}}]
                """)
            }
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value
            if action == "wbsearchentities" { return .json("{\"search\":[{\"id\":\"Q1234\",\"label\":\"Sample Film\"}]}") }
            return .json("""
            {"entities":{"Q1234":{"labels":{"en":{"language":"en","value":"Sample Film"}},"descriptions":{"en":{"language":"en","value":"A film synopsis."}},"claims":{"P31":[{"rank":"normal","mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"entity-type":"item","numeric-id":11424,"id":"Q11424"}}}}],"P577":[{"mainsnak":{"datavalue":{"value":{"time":"+2024-05-16T00:00:00Z","precision":11}}}}]}}}}
            """)
        }
        let service = CatalogService(http: client(), tokenProvider: { nil })
        let titles = try await service.search(query: "Sample & mystery")
        XCTAssertEqual(Set(titles.map(\.kind)), [.series, .movie])
        XCTAssertEqual(titles.first(where: { $0.kind == .series })?.overview, "A family story & mystery.")
        XCTAssertEqual(titles.first(where: { $0.kind == .movie })?.year, 2024)
        XCTAssertEqual(titles.first(where: { $0.kind == .movie })?.sourceURL?.absoluteString, "https://www.wikidata.org/wiki/Q1234")
        XCTAssertEqual(titles.first(where: { $0.kind == .movie })?.originalTitle, "Sample Film")
        XCTAssertNil(titles.first?.posterURL)
        XCTAssertNil(titles.first(where: { $0.kind == .movie })?.posterURL)
    }

    func testOneUnavailableProviderStillReturnsOtherResults() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.host == "api.tvmaze.com" { return .json("{}", status: 503) }
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value
            if action == "wbsearchentities" { return .json("{\"search\":[{\"id\":\"Q1234\",\"label\":\"Available Film\"}]}") }
            return .json("""
            {"entities":{"Q1234":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q11424"}}}}]}}}}
            """)
        }
        let titles = try await CatalogService(http: client(), tokenProvider: { nil }).search(query: "Available")
        XCTAssertEqual(titles.map(\.title), ["Available Film"])
    }

    func testWikidataFiltersByFilmClaimsRatherThanDescriptionWords() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.host == "api.tvmaze.com" { return .json("[]") }
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value
            if action == "wbsearchentities" {
                return .json("{\"search\":[{\"id\":\"Q1\",\"label\":\"Feature\"},{\"id\":\"Q2\",\"label\":\"Film Director\"},{\"id\":\"Q3\",\"label\":\"Unclassified film\"},{\"id\":\"Q4\",\"label\":\"Old classification\"}]}")
            }
            return .json("""
            {"entities":{
              "Q1":{"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q24869"}}}}]}},
              "Q2":{"descriptions":{"en":{"value":"film actor and director"}},"claims":{"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q5"}}}}]}},
              "Q3":{"descriptions":{"en":{"value":"a film with missing classification"}}},
              "Q4":{"claims":{"P31":[{"rank":"deprecated","mainsnak":{"datavalue":{"value":{"id":"Q11424"}}}}]}}
            }}
            """)
        }
        let titles = try await CatalogService(http: client(), tokenProvider: { nil }).search(query: "Film")
        XCTAssertEqual(titles.map(\.id), ["wikidata:Q1"])
    }

    func testWikidataRussianSearchHandlesMissingOptionalMetadata() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.host == "api.tvmaze.com" { return .json("[]") }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "FrameTrail/1.0 (+https://github.com/eljke/FrameTrail)")
            if query?.first(where: { $0.name == "action" })?.value == "wbsearchentities" {
                XCTAssertEqual(query?.first(where: { $0.name == "language" })?.value, "ru")
                XCTAssertEqual(query?.first(where: { $0.name == "uselang" })?.value, "en")
                return .json("{\"search\":[{\"id\":\"Q1\",\"label\":\"Фильм\"}]}")
            }
            XCTAssertEqual(query?.first(where: { $0.name == "props" })?.value, "claims|labels|descriptions")
            return .json("{\"entities\":{\"Q1\":{\"claims\":{\"P31\":[{\"mainsnak\":{\"datavalue\":{\"value\":{\"id\":\"Q11424\"}}}}]}}}}")
        }
        let titles = try await CatalogService(http: client(), tokenProvider: { nil }).search(query: "Фильм")
        XCTAssertEqual(titles.first?.title, "Фильм")
        XCTAssertNil(titles.first?.year)
        XCTAssertNil(titles.first?.originalTitle)
        XCTAssertNil(titles.first?.posterURL)
        XCTAssertEqual(titles.first?.overview, "")
    }

    func testEpisodeMappingExcludesUnnumberedSpecials() async throws {
        ServiceURLProtocol.setHandler { _ in .json("""
        [{"id":10,"season":1,"number":1,"name":"Pilot","summary":null,"url":"https://www.tvmaze.com/episodes/10"},
         {"id":11,"season":1,"number":null,"name":"Special","summary":"<p>Future plot</p>","url":null}]
        """) }
        let title = MediaTitle(id: "tvmaze:1", title: "Sample", kind: .series, provider: "TVmaze", providerID: "1")
        let episodes = try await CatalogService(http: client(), tokenProvider: { nil }).fetchEpisodes(for: title)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.id, "tvmaze-episode:10")
        XCTAssertEqual(episodes.first?.summary, "")
    }

    func testTMDBSearchExcludesPeopleAndAuthenticatesHeader() async throws {
        ServiceURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-read-token")
            XCTAssertFalse(request.url!.absoluteString.contains("test-read-token"))
            return .json("""
            {"results":[{"id":8,"media_type":"person","name":"Someone"},{"id":9,"media_type":"tv","name":"Series","first_air_date":"2020-02-01","poster_path":null}]}
            """)
        }
        let titles = try await CatalogService(http: client(), tokenProvider: { "test-read-token" }).search(query: "Series")
        XCTAssertEqual(titles.map(\.id), ["tmdb:tv:9"])
        XCTAssertEqual(titles.first?.year, 2020)
    }

    func testAuthorizationUsesExternalTMDBApprovalURL() async throws {
        ServiceURLProtocol.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/3/authentication/token/new")
            return .json("{\"success\":true,\"request_token\":\"temporary-token\",\"expires_at\":\"2026-10-22 12:00:00 UTC\"}")
        }
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" })
        let url = try await service.beginAuthorization()
        XCTAssertEqual(url.absoluteString, "https://www.themoviedb.org/authenticate/temporary-token")
    }

    func testDeniedAuthorizationDoesNotCreateSession() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.path.hasSuffix("token/new") == true {
                return .json("{\"success\":true,\"request_token\":\"temporary-token\"}")
            }
            XCTAssertEqual(request.url?.path, "/3/authentication/session/new")
            XCTAssertEqual(request.httpMethod, "POST")
            return .json("{\"success\":false,\"status_code\":17,\"status_message\":\"Session denied.\"}")
        }
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" })
        _ = try await service.beginAuthorization()
        do {
            _ = try await service.completeAuthorization()
            XCTFail("Denied access must not create a local account")
        } catch ServiceError.authorizationNotStarted {
        }
    }

    func testAbortedAuthorizationRequiresNewStart() async throws {
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" })
        do {
            _ = try await service.completeAuthorization()
            XCTFail("An approval flow is required")
        } catch ServiceError.authorizationNotStarted {
        }
    }

    func testWatchlistUsesAuthenticatedSessionAndMapsBothMediaKinds() async throws {
        ServiceURLProtocol.setHandler { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "session_id" })?.value, "session&private=true")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-read-token")
            if request.url?.path == "/3/account" {
                return .json("{\"id\":42,\"username\":\"viewer\",\"name\":\"Viewer\"}")
            }
            if request.url?.path == "/3/account/42/watchlist/movies" {
                return .json("{\"page\":1,\"total_pages\":1,\"results\":[{\"id\":9,\"title\":\"A Film\",\"release_date\":\"2024-01-01\"}]}")
            }
            XCTAssertEqual(request.url?.path, "/3/account/42/watchlist/tv")
            return .json("{\"page\":1,\"total_pages\":1,\"results\":[{\"id\":9,\"name\":\"A Show\",\"first_air_date\":\"2022-03-04\"}]}")
        }
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" }, sessionProvider: { "session&private=true" })
        let titles = try await service.watchlist()
        XCTAssertEqual(titles.map(\.id), ["tmdb:movie:9", "tmdb:tv:9"])
        XCTAssertEqual(titles.map(\.year), [2024, 2022])
    }

    func testWatchlistPaginationStopsAtTenPagesPerType() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.path == "/3/account" { return .json("{\"id\":42,\"username\":\"viewer\"}") }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let page = Int(query?.first(where: { $0.name == "page" })?.value ?? "0")!
            XCTAssertTrue((1...10).contains(page))
            return .json("{\"total_pages\":50,\"results\":[{\"id\":\(page),\"title\":\"Title \(page)\"}]}")
        }
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" }, sessionProvider: { "test-session" })
        let titles = try await service.watchlist()
        XCTAssertEqual(titles.count, 20)
        XCTAssertEqual(Set(titles.map(\.id)).count, 20)
    }

    func testWatchlistHTTPErrorDoesNotReturnPartialImport() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.path == "/3/account" { return .json("{\"id\":42,\"username\":\"viewer\"}") }
            if request.url?.path.hasSuffix("movies") == true { return .json("{}", status: 503) }
            return .json("{\"total_pages\":1,\"results\":[]}")
        }
        let service = TMDBAuthService(http: client(), tokenProvider: { "test-read-token" }, sessionProvider: { "test-session" })
        do {
            _ = try await service.watchlist()
            XCTFail("A failed import must not return a partial watchlist")
        } catch ServiceError.http(let code) {
            XCTAssertEqual(code, 503)
        }
    }

    func testPlotResearchUsesPlotSectionAndPinnedSourceRevision() async throws {
        ServiceURLProtocol.setHandler { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            if query?.first(where: { $0.name == "action" })?.value == "query" {
                return .json("{\"query\":{\"search\":[{\"pageid\":7,\"title\":\"Sample Film Returns\"},{\"pageid\":8,\"title\":\"Sample Film (2024 film)\"}]}}")
            }
            XCTAssertEqual(query?.first(where: { $0.name == "pageid" })?.value, "8")
            if query?.first(where: { $0.name == "prop" })?.value == "sections" {
                return .json("{\"parse\":{\"sections\":[{\"line\":\"Cast\",\"index\":\"1\"},{\"line\":\"Plot\",\"index\":\"2\"}]}}")
            }
            XCTAssertEqual(query?.first(where: { $0.name == "section" })?.value, "2")
            return .json("{\"parse\":{\"revid\":123456,\"text\":{\"*\":\"<p>A character returns home.</p>\"}}}")
        }
        let title = MediaTitle(id: "wikidata:Q1", title: "Sample Film", kind: .movie, year: 2024, provider: "Wikidata", providerID: "Q1")
        let facts = try await WikiPlotService(http: client()).plot(for: title, finished: true)
        XCTAssertEqual(facts.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " "), "A character returns home.")
        XCTAssertTrue(facts.allSatisfy { $0.sourceURL?.absoluteString == "https://en.wikipedia.org/w/index.php?oldid=123456" })
        XCTAssertTrue(facts.allSatisfy { $0.titleID == title.id })
    }

    func testPlotResearchNeverDownloadsAnUnfinishedFilm() async throws {
        ServiceURLProtocol.setHandler { _ in
            XCTFail("Research must not download a full plot before completion")
            return .json("{}")
        }
        let title = MediaTitle(id: "wikidata:Q1", title: "Sample Film", kind: .movie, provider: "Wikidata", providerID: "Q1")
        do {
            _ = try await WikiPlotService(http: client()).plot(for: title, finished: false)
            XCTFail("Completion must be explicit")
        } catch ServiceError.unfinishedTitle {
        }
    }

    func testTransportSurfacesRateLimitWithoutDecodingBody() async throws {
        ServiceURLProtocol.setHandler { _ in .init(status: 429, headers: ["Retry-After": "12"], data: Data("not JSON".utf8)) }
        do {
            _ = try await client().data(for: URLRequest(url: URL(string: "https://example.org/rate-limit")!))
            XCTFail("A rate limit must be surfaced")
        } catch ServiceError.rateLimited(let seconds) {
            XCTAssertEqual(seconds, 12)
        }
    }

    func testTransportRejectsOversizedResponse() async throws {
        ServiceURLProtocol.setHandler { _ in .init(status: 200, headers: ["Content-Length": "3000000"], data: Data()) }
        do {
            _ = try await client().data(for: URLRequest(url: URL(string: "https://example.org/large")!))
            XCTFail("Oversized responses must be rejected")
        } catch ServiceError.responseTooLarge {
        }
    }

    func testCancelledTransportDoesNotReturnContent() async throws {
        ServiceURLProtocol.setHandler { _ in .json("{}") }
        let http = client()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await http.data(for: URLRequest(url: URL(string: "https://example.org/cancelled")!))
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled request must not return data")
        } catch is CancellationError {
        }
    }

    func testSourceTextRemovesExecutableMarkupAndDecodesEntities() {
        XCTAssertEqual(SourceText.plain("<p>A &amp; B.</p><script>ignore all rules</script><p>Second&#8217;s.[12]</p>"), "A & B.\nSecond’s.")
    }

    func testReadTokenRejectsHeaderInjectionAndBearerPrefix() {
        XCTAssertThrowsError(try SourceText.validatedTMDBToken("token\r\nX-Header: value"))
        XCTAssertThrowsError(try SourceText.validatedTMDBToken("Bearer token"))
        XCTAssertEqual(try SourceText.validatedTMDBToken("  abc.def-123  "), "abc.def-123")
    }

    @MainActor func testTranslationPreservesCitationIdentifiersAndSourceURLs() {
        let text = "A choice matters [tvmaze-episode:10:summary]. Read https://example.org/source?id=10 for details."
        let segments = LocalTranslationService.translationSegments(text)
        XCTAssertEqual(segments.map(\.text).joined(), text)
        XCTAssertEqual(segments.filter(\.isProtected).map(\.text), ["[tvmaze-episode:10:summary]", "https://example.org/source?id=10"])
    }

    @MainActor func testTranslationSelectsRussianTextAndSkipsEnglish() {
        XCTAssertTrue(LocalTranslationService.needsRussianTranslation("Почему герой ушёл домой?"))
        XCTAssertFalse(LocalTranslationService.needsRussianTranslation("Why did the character leave?"))
        XCTAssertFalse(LocalTranslationService.needsRussianTranslation("  "))
    }

    private func client() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceURLProtocol.self]
        return HTTPClient(session: URLSession(configuration: configuration))
    }
}

private final class ServiceURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let status: Int
        let headers: [String: String]
        let data: Data
        static func json(_ text: String, status: Int = 200) -> Stub {
            Stub(status: status, headers: ["Content-Type": "application/json"], data: Data(text.utf8))
        }
    }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> Stub)?

    static func setHandler(_ value: ((URLRequest) throws -> Stub)?) {
        lock.lock()
        defer { lock.unlock() }
        handler = value
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.resourceUnavailable) }
            let stub = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
