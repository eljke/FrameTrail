import Foundation

public struct RecommendationCandidate: Sendable, Identifiable {
    public let title: MediaTitle
    public let rating: Double
    public let votes: Int
    public let popularity: Double
    public var id: String { title.id }
    public init(title: MediaTitle, rating: Double, votes: Int, popularity: Double) {
        self.title = title; self.rating = rating; self.votes = votes; self.popularity = popularity
    }
}

public enum RecommendationPool {
    public static func ranked(_ candidates: [RecommendationCandidate], excluding: Set<String>) -> [RecommendationCandidate] {
        var seen = excluding
        return candidates.filter { item in
            item.rating.isFinite && (7...10).contains(item.rating) && item.votes >= (item.title.kind == .movie ? 300 : 150)
                && item.popularity.isFinite && item.popularity >= 0 && seen.insert(item.id).inserted
        }.sorted { lhs, rhs in
            func score(_ item: RecommendationCandidate) -> Double {
                (Double(item.votes) * item.rating + 1000 * 7) / (Double(item.votes) + 1000) + min(log1p(item.popularity), 8) * 0.03
            }
            let left = score(lhs), right = score(rhs)
            return left == right ? lhs.id < rhs.id : left > right
        }
    }
}
