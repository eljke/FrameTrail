import Foundation

struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    init(projectURL: URL, publishableKey: String) throws {
        guard projectURL.scheme == "https", projectURL.host != nil, projectURL.user == nil, projectURL.password == nil,
              projectURL.query == nil, projectURL.fragment == nil, ["", "/"].contains(projectURL.path),
              publishableKey.hasPrefix("sb_publishable_"), !publishableKey.contains(where: \.isWhitespace) else {
            throw SupabaseAuthError.notConfigured
        }
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }

    static func bundled(in bundle: Bundle = .main) throws -> SupabaseConfiguration {
        guard let url = bundle.url(forResource: "Supabase", withExtension: "plist") else { throw SupabaseAuthError.notConfigured }
        let resource = try PropertyListDecoder().decode(Resource.self, from: Data(contentsOf: url))
        guard let projectURL = URL(string: resource.projectURL) else { throw SupabaseAuthError.notConfigured }
        return try SupabaseConfiguration(projectURL: projectURL, publishableKey: resource.publishableKey)
    }

    private struct Resource: Decodable { let projectURL: String; let publishableKey: String }
}

struct SupabaseSession: Codable, Equatable, Sendable {
    let userID: UUID
    let email: String?
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum SupabaseAuthError: LocalizedError, Equatable {
    case notConfigured
    case missingCredentials
    case invalidCredentials
    case emailNotConfirmed
    case emailNotAuthorized
    case weakPassword
    case signupsDisabled
    case sessionExpired
    case rateLimited
    case invalidResponse
    case server(Int)
    case signedOutOffline

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "В этой сборке не настроен сервер аккаунтов FrameTrail. Гостевая библиотека доступна."
        case .missingCredentials: return "Введи email и пароль."
        case .invalidCredentials: return "Неверный email или пароль."
        case .emailNotConfirmed: return "Подтверди email по ссылке из письма, затем войди снова."
        case .emailNotAuthorized: return "Сервер пока отправляет письма только участникам проекта. Для публичной регистрации требуется настройка почты."
        case .weakPassword: return "Пароль не соответствует требованиям сервера. Выбери более длинный и надёжный пароль."
        case .signupsDisabled: return "Регистрация на сервере сейчас отключена."
        case .sessionExpired: return "Сессия завершена. Войди в аккаунт снова."
        case .rateLimited: return "Слишком много попыток входа или писем. Немного подожди и попробуй снова."
        case .invalidResponse: return "Сервер аккаунтов вернул неполный ответ. Попробуй снова."
        case .server(let status): return "Сервер аккаунтов временно недоступен (HTTP \(status))."
        case .signedOutOffline: return "На этом устройстве выполнен выход. Сервер не подтвердил отзыв сессии; доступ по уже выданному токену может сохраняться до его истечения."
        }
    }
}

actor SupabaseAuthService {
    private let config: SupabaseConfiguration
    private let http: HTTPClient
    private let sessionKey: String
    private var revision = UUID()
    private var refreshFlight: RefreshFlight?
    private(set) var session: SupabaseSession?

    init(config: SupabaseConfiguration, http: HTTPClient = .shared, sessionKey: String? = nil) {
        self.config = config
        self.http = http
        self.sessionKey = sessionKey ?? "supabase.session.\(config.projectURL.host!)"
    }

    func restoreSession() async throws -> SupabaseSession? {
        if session == nil { session = try storedSession() }
        return try await currentSession()
    }

    func currentSession() async throws -> SupabaseSession? {
        guard let session else { return nil }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session }
        return try await refresh(session)
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let email = try validate(email: email, password: password)
        let requestRevision = beginOperation()
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await Self.perform(config: config, http: http, path: "token", query: [.init(name: "grant_type", value: "password")], body: body)
        let result = try Self.tokenSession(from: data)
        try Task.checkCancellation()
        guard revision == requestRevision else { throw CancellationError() }
        try persist(result)
        return result
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let email = try validate(email: email, password: password)
        let requestRevision = beginOperation()
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await Self.perform(config: config, http: http, path: "signup", body: body)
        let response: SignupResponse
        do { response = try JSONDecoder().decode(SignupResponse.self, from: data) }
        catch { throw SupabaseAuthError.invalidResponse }
        try Task.checkCancellation()
        guard revision == requestRevision else { throw CancellationError() }
        guard response.access_token != nil else {
            guard response.id != nil || response.user?.id != nil else { throw SupabaseAuthError.invalidResponse }
            return nil
        }
        let result = try Self.tokenSession(from: data)
        try persist(result)
        return result
    }

    func signOut() async throws {
        _ = beginOperation()
        let previous = session ?? (try? storedSession())
        try KeychainStore.set(nil, for: sessionKey)
        session = nil
        guard let previous else { return }
        do {
            _ = try await Self.perform(config: config, http: http, path: "logout", query: [.init(name: "scope", value: "local")], bearer: previous.accessToken)
        } catch {
            throw SupabaseAuthError.signedOutOffline
        }
    }

    func requestPasswordReset(email: String) async throws {
        let email = try validatedEmail(email)
        let body = try JSONEncoder().encode(["email": email])
        _ = try await Self.perform(config: config, http: http, path: "recover", body: body)
    }

    func updatePassword(password: String) async throws {
        guard !password.isEmpty, password.utf8.count <= 4_096 else { throw SupabaseAuthError.missingCredentials }
        let requestRevision = revision
        guard let current = try await currentSession() else { throw SupabaseAuthError.sessionExpired }
        let body = try JSONEncoder().encode(["password": password])
        _ = try await Self.perform(config: config, http: http, path: "user", body: body, bearer: current.accessToken, method: "PUT")
        try Task.checkCancellation()
        guard revision == requestRevision else { throw CancellationError() }
    }

    private func refresh(_ previous: SupabaseSession) async throws -> SupabaseSession {
        let flight: RefreshFlight
        if let existing = refreshFlight { flight = existing }
        else {
            let config = config
            let http = http
            let task = Task<SupabaseSession, Error> {
                let body = try JSONEncoder().encode(["refresh_token": previous.refreshToken])
                let data = try await Self.perform(config: config, http: http, path: "token", query: [.init(name: "grant_type", value: "refresh_token")], body: body)
                return try Self.tokenSession(from: data)
            }
            flight = RefreshFlight(id: UUID(), revision: revision, task: task)
            refreshFlight = flight
        }
        do {
            let renewed = try await flight.task.value
            try Task.checkCancellation()
            guard revision == flight.revision else { throw CancellationError() }
            if refreshFlight?.id == flight.id {
                guard renewed.userID == previous.userID else { throw SupabaseAuthError.invalidResponse }
                try persist(renewed)
                refreshFlight = nil
            }
            return renewed
        } catch {
            if refreshFlight?.id == flight.id { refreshFlight = nil }
            if error as? SupabaseAuthError == .sessionExpired, revision == flight.revision {
                try KeychainStore.set(nil, for: sessionKey)
                session = nil
            }
            throw error
        }
    }

    private func beginOperation() -> UUID {
        revision = UUID()
        refreshFlight?.task.cancel()
        refreshFlight = nil
        return revision
    }

    private func persist(_ value: SupabaseSession) throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw SupabaseAuthError.invalidResponse }
        try KeychainStore.set(text, for: sessionKey)
        session = value
    }

    private func storedSession() throws -> SupabaseSession? {
        guard let stored = try KeychainStore.string(for: sessionKey) else { return nil }
        return try JSONDecoder().decode(SupabaseSession.self, from: Data(stored.utf8))
    }

    private func validate(email: String, password: String) throws -> String {
        let email = try validatedEmail(email)
        guard !password.isEmpty, password.utf8.count <= 4_096 else { throw SupabaseAuthError.missingCredentials }
        return email
    }

    private func validatedEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.count <= 254 else { throw SupabaseAuthError.missingCredentials }
        return email
    }

    private static func tokenSession(from data: Data) throws -> SupabaseSession {
        do { return try JSONDecoder().decode(TokenResponse.self, from: data).session() }
        catch { throw SupabaseAuthError.invalidResponse }
    }

    private static func perform(config: SupabaseConfiguration, http: HTTPClient, path: String, query: [URLQueryItem] = [], body: Data? = nil, bearer: String? = nil, method: String = "POST") async throws -> Data {
        let endpoint = config.projectURL.appendingPathComponent("auth/v1/\(path)")
        let url = try HTTPClient.url(endpoint.absoluteString, query: query)
        var request = HTTPClient.request(url: url, bearer: bearer, method: method, body: body)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await http.response(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(FailureResponse.self, from: data)
            throw authError(code: failure?.error_code, status: response.statusCode)
        }
        return data
    }

    private static func authError(code: String?, status: Int) -> SupabaseAuthError {
        switch code {
        case "invalid_credentials": return .invalidCredentials
        case "email_not_confirmed": return .emailNotConfirmed
        case "email_address_not_authorized": return .emailNotAuthorized
        case "weak_password": return .weakPassword
        case "signup_disabled", "email_provider_disabled": return .signupsDisabled
        case "refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired": return .sessionExpired
        case "over_request_rate_limit", "over_email_send_rate_limit": return .rateLimited
        default: return status == 429 ? .rateLimited : .server(status)
        }
    }

    private struct RefreshFlight {
        let id: UUID
        let revision: UUID
        let task: Task<SupabaseSession, Error>
    }
}

private struct FailureResponse: Decodable { let error_code: String? }
private struct SignupResponse: Decodable {
    let access_token: String?
    let id: UUID?
    let user: TokenResponse.User?
}
private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: TimeInterval
    let expires_at: TimeInterval?
    let user: User
    struct User: Decodable { let id: UUID; let email: String? }

    func session() throws -> SupabaseSession {
        guard !access_token.isEmpty, !refresh_token.isEmpty, expires_in > 0 else { throw SupabaseAuthError.invalidResponse }
        return SupabaseSession(userID: user.id, email: user.email, accessToken: access_token, refreshToken: refresh_token,
                               expiresAt: expires_at.map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(expires_in))
    }
}
