import Foundation

public enum ReviewAspect: String, Codable, CaseIterable, Sendable {
    case characters, relationships, story, dialogue, visuals, pacing

    public var label: String {
        switch self {
        case .characters: return "Персонажи и решения"
        case .relationships: return "Отношения героев"
        case .story: return "Развитие истории"
        case .dialogue: return "Диалоги"
        case .visuals: return "Атмосфера и подача"
        case .pacing: return "Темп повествования"
        }
    }
}

public struct ReviewChoice: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let aspect: ReviewAspect
    public let text: String
    public let sourceQuote: String
    public let sourceID: String
    public let sourceURL: URL?
    public let episodeID: String?

    public init(id: String, aspect: ReviewAspect, text: String, sourceQuote: String, sourceID: String, sourceURL: URL?, episodeID: String?) {
        self.id = id
        self.aspect = aspect
        self.text = text
        self.sourceQuote = sourceQuote
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.episodeID = episodeID
    }
}

public struct ReviewPassage: Identifiable, Hashable, Sendable {
    public let id: String
    public let quote: String
    public let source: StoryFact
    public let ordinal: Int
}

public enum ReviewPassages {
    public static func choice(passageID: String, aspect: ReviewAspect, candidates: [ReviewPassage], localizedQuote: String? = nil) -> ReviewChoice? {
        guard let passage = candidates.first(where: { $0.id == passageID }) else { return nil }
        let id = passage.source.id + "#\(passage.ordinal):" + aspect.rawValue
        let text = aspect.label + " — «" + String((localizedQuote ?? passage.quote).prefix(400)) + "»"
        return ReviewChoice(id: id, aspect: aspect, text: text, sourceQuote: passage.quote, sourceID: passage.source.id, sourceURL: passage.source.sourceURL, episodeID: passage.source.episodeID)
    }

    public static func candidates(in context: GroundedContext) -> [ReviewPassage] {
        var result: [ReviewPassage] = []
        for fact in context.evidence {
            let sourceText = fact.kind == "summary"
                ? fact.text.replacingOccurrences(of: "^S[0-9]+E[0-9]+: ", with: "", options: .regularExpression)
                : fact.text
            let parts = sourceText.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            for (index, part) in parts.enumerated() {
                let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 25 else { continue }
                let quote = String(text.prefix(220))
                if result.contains(where: { $0.quote == quote }) { continue }
                result.append(ReviewPassage(id: "p\(result.count)", quote: quote, source: fact, ordinal: index))
            }
        }
        guard result.count > 12 else { return result }
        return (0..<12).map { result[$0 * (result.count - 1) / 11] }
    }
}
