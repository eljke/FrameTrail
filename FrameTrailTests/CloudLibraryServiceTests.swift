import XCTest
import FrameTrailCore
@testable import FrameTrail

final class CloudLibraryServiceTests: XCTestCase {
    override func tearDown() {
        CloudURLProtocol.handler = nil
        super.tearDown()
    }

    func testReadsEveryPageUsingOwnerSession() async throws {
        let titles = (0..<11).map { MediaTitle(id: String(format: "local:%02d", $0), title: "Film \($0)", kind: .movie, provider: "local", providerID: String($0)) }
        CloudURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-session")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertFalse(query.contains { $0.name == "user_id" })
            let after = query.first { $0.name == "media_id" }?.value
            XCTAssertEqual(query.first { $0.name == "limit" }?.value, "3")
            let cursor = after.map { String($0.dropFirst(3)) }
            let page = Array(titles.filter { cursor == nil || $0.id > cursor! }.prefix(3))
            return (200, try Self.rows(page))
        }
        let records = try await service().fetchAll(accessToken: "owner-session")
        XCTAssertEqual(records.map(\.mediaID), titles.map(\.id))
    }

    func testDeletionSendsNullPayloadAndExpectedRevision() async throws {
        CloudURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/put_library_item")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.testBodyData()) as? [String: Any])
            XCTAssertEqual(body["p_media_id"] as? String, "local:gone")
            XCTAssertEqual(body["p_expected_revision"] as? Int, 4)
            XCTAssertEqual(body["p_deleted"] as? Bool, true)
            XCTAssertTrue(body["p_payload"] is NSNull)
            return (200, Data("[{\"media_id\":\"local:gone\",\"payload\":null,\"revision\":5,\"deleted\":true}]".utf8))
        }
        let result = try await service().put(mediaID: "local:gone", item: nil, expectedRevision: 4, accessToken: "owner-session")
        XCTAssertEqual(result?.revision, 5)
        XCTAssertEqual(result?.deleted, true)
    }

    func testStaleWriteReturnsConflictWithoutInventingSuccess() async throws {
        CloudURLProtocol.handler = { _ in (200, Data("[]".utf8)) }
        let result = try await service().put(mediaID: "local:gone", item: nil, expectedRevision: 4, accessToken: "owner-session")
        XCTAssertNil(result)
    }

    func testRejectsForeignPayloadIdentity() async throws {
        let title = MediaTitle(id: "local:other", title: "Other", kind: .movie, provider: "local", providerID: "other")
        var row = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.rows([title])) as? [[String: Any]])
        row[0]["media_id"] = "local:expected"
        let data = try JSONSerialization.data(withJSONObject: row)
        CloudURLProtocol.handler = { _ in (200, data) }
        do { _ = try await service().fetchAll(accessToken: "owner-session"); XCTFail("Mismatched record must be rejected") }
        catch CloudLibraryError.invalidRecord {}
    }

    func testDeletesOnlyAuthenticatedAccountThroughServerFunction() async throws {
        CloudURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owner-session")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.url?.query)
            return (204, Data())
        }
        try await service().deleteAccount(accessToken: "owner-session")
    }

    private func service() throws -> CloudLibraryService {
        let config = try SupabaseConfiguration(projectURL: URL(string: "https://project.example.org")!, publishableKey: "sb_publishable_test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudURLProtocol.self]
        return CloudLibraryService(config: config, http: HTTPClient(session: URLSession(configuration: configuration)))
    }

    private static func rows(_ titles: [MediaTitle]) throws -> Data {
        let rows = try titles.map { title -> [String: Any] in
            let item = CloudLibraryItem(title: title, progress: WatchProgress(), reflections: [])
            return ["media_id": title.id, "payload": try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)), "revision": 1, "deleted": false]
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }


}

private final class CloudURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
