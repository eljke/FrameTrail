import Foundation

public struct CharacterMention: Sendable {
    public let name: String
    public let sourceID: String
    public let quote: String
    public init(name: String, sourceID: String, quote: String) {
        self.name = name; self.sourceID = sourceID; self.quote = quote
    }
}

public struct StoryPerson: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let sources: [StoryFact]
}

public struct StoryAtlas: Sendable {
    public let people: [StoryPerson]

    public init(context: GroundedContext, mentions: [CharacterMention]) {
        let evidence = Dictionary(context.evidence.filter {
            $0.episodeID.map(context.allowedEpisodeIDs.contains) ?? true
        }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: [StoryFact]] = [:]
        for mention in mentions.prefix(40) {
            let name = mention.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...80).contains(name.count), (12...400).contains(mention.quote.count),
                  let source = evidence[mention.sourceID], source.text.contains(mention.quote),
                  mention.quote.range(of: "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])", options: .regularExpression) != nil else { continue }
            var excerpt = source
            excerpt.text = mention.quote
            if grouped[name]?.contains(where: { $0.id == source.id }) != true { grouped[name, default: []].append(excerpt) }
        }
        people = grouped.keys.sorted().prefix(16).map { StoryPerson(name: $0, sources: Array(grouped[$0]!.prefix(6))) }
    }

    public func companions(of name: String) -> [String] {
        guard let person = people.first(where: { $0.name == name }) else { return [] }
        let sources = Set(person.sources.map(\.id))
        return people.filter { $0.name != name && !$0.sources.allSatisfy { !sources.contains($0.id) } }.map(\.name)
    }
}
