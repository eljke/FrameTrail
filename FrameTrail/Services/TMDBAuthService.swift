import Foundation
import FrameTrailCore

struct AuthAccount: Codable, Hashable, Sendable {
    let id: String
    let username: String
    let displayName: String?
}

actor TMDBAuthService {
    private let http: HTTPClient
    private let tokenProvider: @Sendable () throws -> String?
    private let sessionProvider: @Sendable () throws -> String?
    private var pendingRequestToken: String?
    private let sessionKey = "tmdb.session-id"
    private let accountKey = "tmdb.account"

    init(http: HTTPClient = .shared, tokenProvider: @escaping @Sendable () throws -> String? = {
        try KeychainStore.string(for: CatalogService.tmdbTokenKey)
    }, sessionProvider: @escaping @Sendable () throws -> String? = {
        try KeychainStore.string(for: "tmdb.session-id")
    }) {
        self.http = http
        self.tokenProvider = tokenProvider
        self.sessionProvider = sessionProvider
    }

    func hasTMDBReadToken() throws -> Bool {
        try tokenProvider() != nil
    }

    func setTMDBReadToken(_ token: String?) async throws {
        let token = try SourceText.validatedTMDBToken(token)
        let previous = try KeychainStore.string(for: CatalogService.tmdbTokenKey)
        guard previous != token else { return }
        if let token {
            let url = try HTTPClient.url("https://api.themoviedb.org/3/authentication")
            let result = try await http.decode(AuthenticationValidation.self, request: HTTPClient.request(url: url, bearer: token))
            guard result.success else { throw ServiceError.http(401) }
        }
        if try KeychainStore.string(for: sessionKey) != nil { try await logout() }
        try KeychainStore.set(token, for: CatalogService.tmdbTokenKey)
        pendingRequestToken = nil
    }

    func beginAuthorization() async throws -> URL {
        let token = try readToken()
        let url = try HTTPClient.url("https://api.themoviedb.org/3/authentication/token/new")
        let response = try await http.decode(RequestTokenResponse.self, request: HTTPClient.request(url: url, bearer: token))
        guard response.success, let requestToken = response.request_token, !requestToken.isEmpty else { throw ServiceError.authorizationNotStarted }
        pendingRequestToken = requestToken
        return try HTTPClient.url("https://www.themoviedb.org/authenticate/\(requestToken)")
    }

    func completeAuthorization() async throws -> AuthAccount {
        guard let requestToken = pendingRequestToken else { throw ServiceError.authorizationNotStarted }
        let token = try readToken()
        let url = try HTTPClient.url("https://api.themoviedb.org/3/authentication/session/new")
        let body = try JSONEncoder().encode(["request_token": requestToken])
        let session = try await http.decode(SessionResponse.self, request: HTTPClient.request(url: url, bearer: token, method: "POST", body: body))
        guard session.success, let sessionID = session.session_id, !sessionID.isEmpty else { throw ServiceError.authorizationNotStarted }
        do {
            let account = try await fetchAccount(sessionID: sessionID, token: token)
            let accountData = try JSONEncoder().encode(account)
            guard let accountText = String(data: accountData, encoding: .utf8) else { throw ServiceError.invalidResponse }
            try KeychainStore.set(accountText, for: accountKey)
            do { try KeychainStore.set(sessionID, for: sessionKey) }
            catch {
                try? KeychainStore.set(nil, for: accountKey)
                throw error
            }
            pendingRequestToken = nil
            return account
        } catch {
            try? await revoke(sessionID: sessionID, token: token)
            throw error
        }
    }

    func cachedAccount() throws -> AuthAccount? {
        guard try KeychainStore.string(for: sessionKey) != nil,
              let text = try KeychainStore.string(for: accountKey) else { return nil }
        return try JSONDecoder().decode(AuthAccount.self, from: Data(text.utf8))
    }

    func account() async throws -> AuthAccount? {
        guard let session = try sessionProvider() else { return nil }
        return try await fetchAccount(sessionID: session, token: readToken())
    }

    func watchlist() async throws -> [MediaTitle] {
        guard let session = try sessionProvider() else { throw ServiceError.authorizationNotStarted }
        let token = try readToken()
        let account = try await fetchAccount(sessionID: session, token: token)
        async let movies = watchlist(kind: .movie, accountID: account.id, sessionID: session, token: token)
        async let series = watchlist(kind: .series, accountID: account.id, sessionID: session, token: token)
        return try await movies + series
    }

    private func watchlist(kind: MediaKind, accountID: String, sessionID: String, token: String) async throws -> [MediaTitle] {
        let path = kind == .movie ? "movies" : "tv"
        var titles: [MediaTitle] = []
        for pageNumber in 1...10 {
            try Task.checkCancellation()
            let url = try HTTPClient.url("https://api.themoviedb.org/3/account/\(accountID)/watchlist/\(path)", query: [
                .init(name: "session_id", value: sessionID), .init(name: "page", value: String(pageNumber)),
                .init(name: "language", value: "en-US"), .init(name: "sort_by", value: "created_at.desc")
            ])
            let page = try await http.decode(TMDBPage.self, request: HTTPClient.request(url: url, bearer: token))
            titles.append(contentsOf: page.results.compactMap { $0.mediaTitle(as: kind) })
            if pageNumber >= (page.total_pages ?? 1) || page.results.isEmpty { break }
        }
        return titles
    }

    func logout() async throws {
        let session = try KeychainStore.string(for: sessionKey)
        let token = try KeychainStore.string(for: CatalogService.tmdbTokenKey)
        var revokeFailed = false
        if let session, let token {
            do { try await revoke(sessionID: session, token: token) }
            catch { revokeFailed = true }
        }
        try localSignOut()
        if revokeFailed { throw ServiceError.signedOutOffline }
    }

    private func localSignOut() throws {
        try KeychainStore.set(nil, for: sessionKey)
        try KeychainStore.set(nil, for: accountKey)
        pendingRequestToken = nil
    }

    private func readToken() throws -> String {
        guard let token = try tokenProvider(), !token.isEmpty else { throw ServiceError.missingTMDBToken }
        return token
    }

    private func fetchAccount(sessionID: String, token: String) async throws -> AuthAccount {
        let url = try HTTPClient.url("https://api.themoviedb.org/3/account", query: [.init(name: "session_id", value: sessionID)])
        let response = try await http.decode(AccountResponse.self, request: HTTPClient.request(url: url, bearer: token))
        return AuthAccount(id: String(response.id), username: response.username,
                           displayName: response.name.flatMap { $0.isEmpty ? nil : $0 })
    }

    private func revoke(sessionID: String, token: String) async throws {
        let url = try HTTPClient.url("https://api.themoviedb.org/3/authentication/session")
        let body = try JSONEncoder().encode(["session_id": sessionID])
        _ = try await http.data(for: HTTPClient.request(url: url, bearer: token, method: "DELETE", body: body))
    }
}

private struct RequestTokenResponse: Decodable, Sendable {
    let success: Bool
    let request_token: String?
}
private struct SessionResponse: Decodable, Sendable {
    let success: Bool
    let session_id: String?
}
private struct AccountResponse: Decodable, Sendable {
    let id: Int
    let username: String
    let name: String?
}
private struct AuthenticationValidation: Decodable, Sendable { let success: Bool }
