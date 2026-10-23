import XCTest
@testable import FrameTrail

final class SupabaseAuthTests: XCTestCase {
    private var sessionKey = ""
    private let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    override func setUp() {
        super.setUp()
        sessionKey = "supabase.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? KeychainStore.set(nil, for: sessionKey)
        AuthURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testSignInPersistsSessionInKeychainAndRestoresWithoutPassword() async throws {
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query, "grant_type=password")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            XCTAssertEqual(body, ["email": "viewer@example.org", "password": "test-password"])
            return .json(Self.tokenJSON())
        }
        let service = try service()
        let signedIn = try await service.signIn(email: " viewer@example.org ", password: "test-password")
        XCTAssertEqual(signedIn.userID, userID)
        let stored = try XCTUnwrap(KeychainStore.string(for: sessionKey))
        XCTAssertFalse(stored.contains("test-password"))
        XCTAssertEqual(try JSONDecoder().decode(SupabaseSession.self, from: Data(stored.utf8)), signedIn)
        AuthURLProtocol.setHandler { _ in XCTFail("An unexpired session must restore locally"); return .json("{}") }
        let restored = try await self.service().restoreSession()
        XCTAssertEqual(restored, signedIn)
    }

    func testSignupRequiringConfirmationDoesNotCreateLocalSession() async throws {
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/signup")
            return .json("{\"id\":\"11111111-2222-3333-4444-555555555555\",\"email\":\"viewer@example.org\",\"identities\":[]}")
        }
        let service = try service()
        let result = try await service.signUp(email: "viewer@example.org", password: "test-password")
        XCTAssertNil(result)
        let cached = await service.session
        XCTAssertNil(cached)
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testConcurrentRestorationRefreshesOnceAndPersistsRotatedToken() async throws {
        try saveExpiredSession()
        let refreshed = expectation(description: "one refresh request")
        refreshed.assertForOverFulfill = true
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query, "grant_type=refresh_token")
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: request.httpBody!), ["refresh_token": "refresh-old"])
            refreshed.fulfill()
            Thread.sleep(forTimeInterval: 0.05)
            return .json(Self.tokenJSON(refresh: "refresh-rotated"))
        }
        let service = try service()
        async let first = service.restoreSession()
        async let second = service.restoreSession()
        let sessions = try await [first, second]
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(sessions.compactMap { $0?.refreshToken }, ["refresh-rotated", "refresh-rotated"])
        let stored = try XCTUnwrap(KeychainStore.string(for: sessionKey))
        XCTAssertEqual(try JSONDecoder().decode(SupabaseSession.self, from: Data(stored.utf8)).refreshToken, "refresh-rotated")
    }

    func testUnconfirmedEmailUsesTypedProviderError() async throws {
        AuthURLProtocol.setHandler { _ in .json("{\"code\":400,\"error_code\":\"email_not_confirmed\",\"msg\":\"Email not confirmed\"}", status: 400) }
        do {
            _ = try await service().signIn(email: "viewer@example.org", password: "test-password")
            XCTFail("An unconfirmed address must not sign in")
        } catch SupabaseAuthError.emailNotConfirmed {
        }
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testInvalidRefreshRemovesExpiredSession() async throws {
        try saveExpiredSession()
        AuthURLProtocol.setHandler { _ in .json("{\"error_code\":\"refresh_token_not_found\",\"msg\":\"Invalid refresh token\"}", status: 400) }
        let service = try service()
        do {
            _ = try await service.restoreSession()
            XCTFail("A revoked refresh token must require sign-in")
        } catch SupabaseAuthError.sessionExpired {
        }
        let cached = await service.session
        XCTAssertNil(cached)
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testTemporaryRefreshFailurePreservesOfflineIdentityAndCredentials() async throws {
        try saveExpiredSession()
        AuthURLProtocol.setHandler { _ in .json("{}", status: 503) }
        let service = try service()
        do {
            _ = try await service.restoreSession()
            XCTFail("An offline refresh must report its failure")
        } catch SupabaseAuthError.server(let status) {
            XCTAssertEqual(status, 503)
        }
        let cached = await service.session
        XCTAssertEqual(cached?.userID, userID)
        XCTAssertNotNil(try KeychainStore.string(for: sessionKey))
    }

    func testSignoutClearsKeychainEvenWhenRemoteRevocationFails() async throws {
        let stored = SupabaseSession(userID: userID, email: "viewer@example.org", accessToken: "access-old", refreshToken: "refresh-old", expiresAt: Date().addingTimeInterval(3_600))
        try save(stored)
        let service = try service()
        _ = try await service.restoreSession()
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/logout")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query, "scope=local")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-old")
            return .json("{}", status: 503)
        }
        do { try await service.signOut(); XCTFail("Remote failure should remain visible") }
        catch SupabaseAuthError.signedOutOffline {}
        let cached = await service.session
        XCTAssertNil(cached)
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testSignoutWhileSigninIsPendingDoesNotRestoreCredentials() async throws {
        let started = expectation(description: "sign-in started")
        AuthURLProtocol.setHandler { _ in
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.1)
            return .json(Self.tokenJSON())
        }
        let service = try service()
        let pending = Task { try await service.signIn(email: "viewer@example.org", password: "test-password") }
        await fulfillment(of: [started], timeout: 2)
        try await service.signOut()
        do { _ = try await pending.value; XCTFail("Sign-out supersedes a pending sign-in") }
        catch is CancellationError {}
        let cached = await service.session
        XCTAssertNil(cached)
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testSignoutWhileRefreshIsPendingDoesNotRestoreCredentials() async throws {
        try saveExpiredSession()
        let started = expectation(description: "refresh started")
        AuthURLProtocol.setHandler { request in
            if request.url?.path.hasSuffix("logout") == true { return .json("") }
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.1)
            return .json(Self.tokenJSON())
        }
        let service = try service()
        let pending = Task { try await service.restoreSession() }
        await fulfillment(of: [started], timeout: 2)
        try await service.signOut()
        _ = try? await pending.value
        let cached = await service.session
        XCTAssertNil(cached)
        XCTAssertNil(try KeychainStore.string(for: sessionKey))
    }

    func testPasswordChangeUsesAuthenticatedUserEndpoint() async throws {
        try save(SupabaseSession(userID: userID, email: nil, accessToken: "access-old", refreshToken: "refresh-old", expiresAt: Date().addingTimeInterval(3_600)))
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-old")
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: request.httpBody!), ["password": "new-password"])
            return .json("{\"id\":\"11111111-2222-3333-4444-555555555555\"}")
        }
        let service = try service()
        _ = try await service.restoreSession()
        try await service.updatePassword(password: "new-password")
    }

    func testPasswordResetDoesNotSendExistingAccessToken() async throws {
        AuthURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/recover")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: request.httpBody!), ["email": "viewer@example.org"])
            return .json("{}")
        }
        try await service().requestPasswordReset(email: "viewer@example.org")
    }

    func testConfigurationRejectsPrivilegedKeysAndNonHTTPSURLs() {
        XCTAssertThrowsError(try SupabaseConfiguration(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_secret_private"))
        XCTAssertThrowsError(try SupabaseConfiguration(projectURL: URL(string: "http://example.supabase.co")!, publishableKey: "sb_publishable_test"))
    }

    private func service() throws -> SupabaseAuthService {
        let config = try SupabaseConfiguration(projectURL: URL(string: "https://project.example.org")!, publishableKey: "sb_publishable_test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocol.self]
        return SupabaseAuthService(config: config, http: HTTPClient(session: URLSession(configuration: configuration)), sessionKey: sessionKey)
    }

    private func saveExpiredSession() throws {
        try save(SupabaseSession(userID: userID, email: "viewer@example.org", accessToken: "access-old", refreshToken: "refresh-old", expiresAt: Date().addingTimeInterval(-1)))
    }

    private func save(_ session: SupabaseSession) throws {
        try KeychainStore.set(String(decoding: JSONEncoder().encode(session), as: UTF8.self), for: sessionKey)
    }

    private static func tokenJSON(refresh: String = "refresh-new") -> String {
        "{\"access_token\":\"access-new\",\"token_type\":\"bearer\",\"refresh_token\":\"\(refresh)\",\"expires_in\":3600,\"expires_at\":4102444800,\"user\":{\"id\":\"11111111-2222-3333-4444-555555555555\",\"email\":\"viewer@example.org\"}}"
    }
}

private final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let status: Int
        let data: Data
        static func json(_ text: String, status: Int = 200) -> Stub { Stub(status: status, data: Data(text.utf8)) }
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
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}
