import Foundation

enum ServiceError: LocalizedError {
    case invalidResponse
    case responseTooLarge
    case http(Int)
    case rateLimited(Int?)
    case missingTMDBToken
    case invalidTMDBToken
    case authorizationNotStarted
    case noPlot
    case unfinishedTitle
    case signedOutOffline

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Не удалось прочитать ответ сервиса. Попробуй ещё раз."
        case .responseTooLarge: return "Ответ превышает лимит загрузки приложения."
        case .http(401), .http(403): return "Сервис отклонил запрос. Если это TMDB, проверь API-токен или войди в аккаунт снова."
        case .http(404): return "Произведение больше не доступно у этого источника."
        case .http(let code): return "Сервис временно недоступен (HTTP \(code)). Попробуй позже."
        case .rateLimited(let seconds):
            return seconds.map { "Слишком много запросов. Попробуй через \($0) с." } ?? "Слишком много запросов. Немного подожди."
        case .missingTMDBToken: return "Перед входом добавь TMDB API Read Access Token в настройках."
        case .invalidTMDBToken: return "Вставь сам TMDB API Read Access Token, без префикса Bearer и переносов строк."
        case .authorizationNotStarted: return "Начни вход заново, подтверди доступ на сайте TMDB и вернись в приложение."
        case .noPlot: return "Подходящий пересказ не найден. Можно добавить свой текст или субтитры."
        case .unfinishedTitle: return "Полный сюжет доступен после отметки о просмотре фильма или выбранной серии."
        case .signedOutOffline: return "На устройстве выполнен выход. Отозвать сессию на TMDB не удалось; при необходимости удали её в подключённых приложениях аккаунта TMDB."
        }
    }
}

actor HTTPClient {
    static let shared = HTTPClient()
    private let session: URLSession
    private let maximumBytes = 2 * 1_024 * 1_024

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: configuration)
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let payload = try await data(for: request)
        return try JSONDecoder().decode(type, from: payload)
    }

    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await self.response(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 429 {
                throw ServiceError.rateLimited(response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
            }
            throw ServiceError.http(response.statusCode)
        }
        return data
    }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw ServiceError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw ServiceError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    static func request(url: URL, bearer: String? = nil, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FrameTrail/1.0 (+https://github.com/eljke/FrameTrail)", forHTTPHeaderField: "User-Agent")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    static func url(_ base: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base) else { throw ServiceError.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ServiceError.invalidResponse }
        return url
    }
}

enum SourceText {
    static func plain(_ html: String?) -> String {
        guard let html else { return "" }
        var text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<(?:br\\s*/?|/p|/div|/li|/h[1-6])>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&lsquo;", "‘"), ("&rsquo;", "’"), ("&ldquo;", "“"), ("&rdquo;", "”")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if let expression = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let entityRange = Range(match.range, in: text), let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[valueRange])
                let value = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(entityRange, with: String(scalar)) }
            }
        }
        text = text.replacingOccurrences(of: "\\[[0-9]+\\]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validatedTMDBToken(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return nil }
        guard token.count <= 4_096, token.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw ServiceError.invalidTMDBToken
        }
        return token
    }
}
