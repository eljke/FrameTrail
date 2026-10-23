import Foundation

public struct NameAlias: Hashable, Codable, Sendable {
    public var original: String
    public var russian: String

    public init(original: String, russian: String) {
        self.original = original
        self.russian = russian
    }
}

public struct ProtectedTranslationText: Sendable {
    public let text: String
    private let replacements: [String: String]

    public init(text: String, names: [String: String]) {
        let names = names.filter { !$0.key.isEmpty }.sorted { $0.key.count > $1.key.count }
        guard !names.isEmpty else { self.text = text; replacements = [:]; return }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + names.map { NSRegularExpression.escapedPattern(for: $0.key) }.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        let expression = try! NSRegularExpression(pattern: pattern)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        var replacements: [String: String] = [:]
        for (index, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            var token = "⟪FT\(index)⟫"
            while text.contains(token) { token = "⟪" + token + "⟫" }
            let original = String(text[range])
            replacements[token] = names.first { $0.key == original }!.value
            result.replaceSubrange(range, with: token)
        }
        self.text = result
        self.replacements = replacements
    }

    public func restored(_ translated: String) -> String? {
        var result = translated
        for (token, name) in replacements {
            guard result.components(separatedBy: token).count == 2 else { return nil }
            result = result.replacingOccurrences(of: token, with: name)
        }
        return result
    }
}
