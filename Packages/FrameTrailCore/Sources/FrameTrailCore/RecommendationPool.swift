import Foundation

public struct RecommendationCandidate: Sendable, Identifiable {
    public let title: MediaTitle
    public let rating: Double
    public let votes: Int
    public let popularity: Double
    public let runtimeMinutes: Int?
    public var id: String { title.id }
    public init(title: MediaTitle, rating: Double, votes: Int, popularity: Double, runtimeMinutes: Int? = nil) {
        self.title = title; self.rating = rating; self.votes = votes; self.popularity = popularity
        self.runtimeMinutes = runtimeMinutes
    }
}

public struct RecommendationBrief: Sendable, Equatable {
    public var kind: MediaKind?
    public var maximumMinutes: Int?
    public var request: String

    public init(kind: MediaKind? = nil, maximumMinutes: Int? = nil, request: String = "") {
        self.kind = kind
        self.maximumMinutes = maximumMinutes.map { min(600, max(1, $0)) }
        self.request = String(request.prefix(1500))
    }

    public func accepts(_ candidate: RecommendationCandidate) -> Bool {
        if let kind, candidate.title.kind != kind { return false }
        if let maximumMinutes {
            guard let runtime = candidate.runtimeMinutes, runtime > 0, runtime <= maximumMinutes else { return false }
        }
        return true
    }
}

public enum RecommendationPool {
    public static func ranked(_ candidates: [RecommendationCandidate], excluding: Set<String>, excludingTitles: [MediaTitle] = []) -> [RecommendationCandidate] {
        var seen = excluding
        var known: [String: Set<Int>] = [:]
        for title in excludingTitles {
            for key in identityKeys(title) { known[key, default: []].insert(title.year ?? 0) }
        }
        return candidates.filter { item in
            let alreadyKnown = identityKeys(item.title).contains { key in
                guard let years = known[key] else { return false }
                return years.contains(0) || item.title.year == nil || years.contains(item.title.year!)
            }
            return !alreadyKnown && item.rating.isFinite && (7...10).contains(item.rating) && item.votes >= (item.title.kind == .movie ? 300 : 150)
                && item.popularity.isFinite && item.popularity >= 0 && seen.insert(item.id).inserted
        }.sorted { lhs, rhs in
            func score(_ item: RecommendationCandidate) -> Double {
                (Double(item.votes) * item.rating + 1000 * 7) / (Double(item.votes) + 1000) + min(log1p(item.popularity), 8) * 0.03
            }
            let left = score(lhs), right = score(rhs)
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    private static func identityKeys(_ title: MediaTitle) -> Set<String> {
        Set([title.title, title.originalTitle].compactMap { $0 }.map { name in
            let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
            return title.kind.rawValue + "|" + normalized
        }.filter { !$0.hasSuffix("|") })
    }
}
