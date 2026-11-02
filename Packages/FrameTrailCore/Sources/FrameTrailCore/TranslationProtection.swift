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
        let protected = Dictionary(grouping: segments.filter(\.isProtected), by: \.text)
        return protected.allSatisfy { name, occurrences in
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
            let expression = try! NSRegularExpression(pattern: pattern)
            return expression.numberOfMatches(in: result, range: NSRange(result.startIndex..., in: result)) == occurrences.count
        }
    }
}
