import Foundation

public struct TasteSample: Sendable {
    public let title: MediaTitle
    public let progress: WatchProgress
    public let reviews: [Reflection]
    public init(title: MediaTitle, progress: WatchProgress, reviews: [Reflection]) {
        self.title = title; self.progress = progress; self.reviews = reviews
    }
}

public struct TastePortrait: Sendable {
    public let context: GroundedContext
    public init(samples: [TasteSample]) {
        var facts: [StoryFact] = []
        for sample in samples.sorted(by: { $0.title.id < $1.title.id }) {
            let latest = sample.eligibleReviews
            for review in latest.prefix(3) {
                let content = [sample.title.title, review.rating.map { "Viewer rating: \($0)/10" } ?? "", review.summary,
                    "Liked: " + review.allLiked.joined(separator: "; "), "Disliked: " + review.allDisliked.joined(separator: "; ")].joined(separator: "\n")
                facts.append(StoryFact(id: "review:\(review.id)", text: String(content.prefix(1200)), kind: "personal-review", titleID: sample.title.id))
            }
            if facts.count >= 12 { break }
        }
        facts = Array(facts.prefix(12))
        context = GroundedContext(text: facts.map(\.text).joined(separator: "\n\n"), evidence: facts, coverage: "Personal reviews only", allowedEpisodeIDs: [], titleName: "Personal viewing impressions", scopeDescription: "These are the viewer's opinions, never objective plot evidence. Infer tentative taste patterns only; do not diagnose personality, invent preferences or reveal story events.")
    }
}
