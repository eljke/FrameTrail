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
        case .invalidResponse: return "The service returned an unreadable response. Please try again."
        case .responseTooLarge: return "This response exceeds the app’s download limit."
        case .http(401), .http(403): return "The service did not authorize this request. Check your TMDB read token or sign in again."
        case .http(404): return "This title is no longer available from its source."
        case .http(let code): return "The service is temporarily unavailable (HTTP \(code)). Please try again."
        case .rateLimited(let seconds):
            return seconds.map { "Too many requests. Try again in \($0) seconds." } ?? "Too many requests. Please wait a moment."
        case .missingTMDBToken: return "Add your TMDB API Read Access Token in Settings before connecting an account."
        case .invalidTMDBToken: return "Paste the TMDB API Read Access Token itself, without a Bearer prefix or line breaks."
        case .authorizationNotStarted: return "Start sign-in again, approve access on TMDB, then return to complete it."
        case .noPlot: return "No matching plot was found. You can import your own notes or subtitles instead."
        case .unfinishedTitle: return "Full plot research is available only after you mark the film as finished."
        case .signedOutOffline: return "You are signed out on this device. TMDB could not revoke the session online; remove it from your TMDB account’s connected applications if needed."
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
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 429 {
                throw ServiceError.rateLimited(response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
            }
            throw ServiceError.http(response.statusCode)
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw ServiceError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw ServiceError.responseTooLarge }
            data.append(byte)
        }
        return data
    }

    static func request(url: URL, bearer: String? = nil, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FrameTrail/1.0 (iOS; movie companion)", forHTTPHeaderField: "User-Agent")
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
