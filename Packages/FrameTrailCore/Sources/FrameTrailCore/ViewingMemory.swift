import Foundation

extension TasteSample {
    public var eligibleReviews: [Reflection] {
        let eligible = reviews.filter { review in
            guard review.titleID == title.id else { return false }
            if let episodeID = review.episodeID { return title.kind == .series && progress.watchedEpisodeIDs.contains(episodeID) }
            return progress.finished
        }
        return Dictionary(grouping: eligible, by: \.scope).values.compactMap { records in
            Reflection.latest(in: records, episodeID: records[0].episodeID, seasonNumber: records[0].seasonNumber)
        }.filter(\.hasContent).sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
    }
}

public enum ViewingMemory {
    public static func context(samples: [TasteSample], query: String) -> GroundedContext {
        let terms = Set(normalized(query).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        var ranked: [(StoryFact, Int, Date)] = []
        for sample in samples {
            for review in sample.eligibleReviews {
                let scope = review.episodeID.map { "Episode: \($0)" } ?? review.seasonNumber.map { "Season: \($0)" } ?? "Whole title"
                let text = [sample.title.title, scope, review.rating.map { "Viewer rating: \($0)/10" } ?? "", review.summary,
                    "Liked: " + review.allLiked.joined(separator: "; "), "Disliked: " + review.allDisliked.joined(separator: "; "),
                    "Questions: " + review.questions.joined(separator: "; ")].joined(separator: "\n")
                let haystack = normalized(text)
                let score = terms.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
                guard terms.isEmpty || score > 0 else { continue }
                ranked.append((StoryFact(id: "review:\(review.id)", text: String(text.prefix(1200)), kind: "personal-review", titleID: sample.title.id), score, review.createdAt))
            }
        }
        ranked.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.2 == b.2 ? a.0.id < b.0.id : a.2 > b.2
        }
        let facts = Array(ranked.prefix(24).map { $0.0 })
        return GroundedContext(text: facts.map(\.text).joined(separator: "\n\n"), evidence: facts,
            coverage: "Up to 24 relevant personal records; literal text search, not exhaustive semantic retrieval",
            allowedEpisodeIDs: [], titleName: "My viewing diary",
            scopeDescription: "Only the viewer's saved opinions of watched material. Quote these records, never invent memories or infer plot facts. Search results may be incomplete.")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
