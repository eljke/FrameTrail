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
            return .json("""
            {"resultCount":1,"results":[{"wrapperType":"track","kind":"feature-movie","trackId":1234,"trackName":"Sample Film","releaseDate":"2024-05-16T07:00:00Z","longDescription":"A film synopsis.","trackViewUrl":"https://itunes.apple.com/movie/id1234"}]}
            """)
        }
        let service = CatalogService(http: client(), tokenProvider: { nil })
        let titles = try await service.search(query: "Sample & mystery")
        XCTAssertEqual(Set(titles.map(\.kind)), [.series, .movie])
        XCTAssertEqual(titles.first(where: { $0.kind == .series })?.overview, "A family story & mystery.")
        XCTAssertEqual(titles.first(where: { $0.kind == .movie })?.year, 2024)
        XCTAssertNil(titles.first?.posterURL)
    }

    func testOneUnavailableProviderStillReturnsOtherResults() async throws {
        ServiceURLProtocol.setHandler { request in
            if request.url?.host == "api.tvmaze.com" { return .json("{}", status: 503) }
            return .json("""
            {"results":[{"trackId":1234,"trackName":"Available Film","releaseDate":"2022-01-01T00:00:00Z"}]}
            """)
        }
        let titles = try await CatalogService(http: client(), tokenProvider: { nil }).search(query: "Available")
        XCTAssertEqual(titles.map(\.title), ["Available Film"])
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
        let title = MediaTitle(id: "itunes:1", title: "Sample Film", kind: .movie, year: 2024, provider: "Apple iTunes", providerID: "1")
        let facts = try await WikiPlotService(http: client()).plot(for: title, finished: true)
        XCTAssertEqual(facts.map(\.text), ["A character returns home."])
        XCTAssertEqual(facts.first?.sourceURL?.absoluteString, "https://en.wikipedia.org/w/index.php?oldid=123456")
        XCTAssertEqual(facts.first?.titleID, title.id)
    }

    func testPlotResearchNeverDownloadsAnUnfinishedFilm() async throws {
        ServiceURLProtocol.setHandler { _ in
            XCTFail("Research must not download a full plot before completion")
            return .json("{}")
        }
        let title = MediaTitle(id: "itunes:1", title: "Sample Film", kind: .movie, provider: "Apple iTunes", providerID: "1")
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
