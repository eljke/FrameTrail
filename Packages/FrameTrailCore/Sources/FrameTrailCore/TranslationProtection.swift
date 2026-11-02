import Foundation

public struct TranslationProtection: Sendable {
    public struct Segment: Sendable {
        public let text: String
        public let isProtected: Bool
    }

    public let segments: [Segment]

    public init(text: String, names: [String: String]) {
        let keys = names.keys.filter { !$0.isEmpty }.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        guard !keys.isEmpty else { segments = [Segment(text: text, isProtected: false)]; return }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + keys.map(NSRegularExpression.escapedPattern).joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        let expression = try! NSRegularExpression(pattern: pattern)
        var result: [Segment] = []
        var start = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if start < range.lowerBound { result.append(Segment(text: String(text[start..<range.lowerBound]), isProtected: false)) }
            result.append(Segment(text: names[String(text[range])]!, isProtected: true))
            start = range.upperBound
        }
        if start < text.endIndex { result.append(Segment(text: String(text[start...]), isProtected: false)) }
        segments = result
    }

    public func accepts(_ result: String) -> Bool {
        let expected = Dictionary(grouping: segments.filter(\.isProtected), by: \.text).mapValues(\.count)
        guard !expected.isEmpty else { return true }
        let names = expected.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + names.map(NSRegularExpression.escapedPattern).joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        let expression = try! NSRegularExpression(pattern: pattern)
        var actual: [String: Int] = [:]
        for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            guard let range = Range(match.range, in: result) else { continue }
            actual[String(result[range]), default: 0] += 1
        }
        return actual == expected
    }
}
