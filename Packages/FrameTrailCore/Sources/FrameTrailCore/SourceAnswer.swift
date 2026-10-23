import Foundation

public struct AnswerParagraph: Sendable {
    public let text: String
    public let sourceIDs: [String]

    public init(text: String, sourceIDs: [String]) {
        self.text = text
        self.sourceIDs = sourceIDs
    }
}

public struct AnswerCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var number: Int
    public var quote: String
    public var sourceURL: URL?

    public var label: String {
        let host = sourceURL?.host ?? ""
        if host.hasSuffix("wikipedia.org") { return "Wikipedia" }
        if host.hasSuffix("themoviedb.org") { return "TMDB" }
        if host.hasSuffix("tvmaze.com") { return "TVmaze" }
        return host
    }
}

public struct SourceAnswer: Sendable {
    public let text: String
    public let citations: [AnswerCitation]

    public init(paragraphs: [AnswerParagraph], evidence: [StoryFact]) {
        let sources = Dictionary(uniqueKeysWithValues: evidence.enumerated().map { ("R\($0.offset + 1)", $0.element) })
        var citations: [AnswerCitation] = []
        var sections: [String] = []
        for paragraph in paragraphs.prefix(4) {
            let ids = Array(Set(paragraph.sourceIDs.prefix(6))).sorted()
            guard !ids.isEmpty, ids.allSatisfy({ sources[$0] != nil }) else { continue }
            let text = Self.visibleText(String(paragraph.text.prefix(2_000)))
                .replacingOccurrences(of: "\\[\\s*[0-9]+(?:\\s*,\\s*[0-9]+)*\\s*\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            var numbers: [Int] = []
            for id in ids {
                let source = sources[id]!
                if let citation = citations.first(where: { $0.id == source.id }) {
                    numbers.append(citation.number)
                } else {
                    let number = citations.count + 1
                    citations.append(AnswerCitation(id: source.id, number: number, quote: String(source.text.prefix(1_200)), sourceURL: source.sourceURL))
                    numbers.append(number)
                }
            }
            sections.append(text + " [" + numbers.map(String.init).joined(separator: ", ") + "]")
        }
        self.text = sections.joined(separator: "\n\n")
        self.citations = citations
    }

    public static func visibleText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[(?:wikipedia:|tmdb:|tvmaze:|movie:|episode:|user:|S[0-9]+E[0-9]+|R[0-9]+)[^\\]\\n]*\\]", with: " ", options: .regularExpression)
    }
}
