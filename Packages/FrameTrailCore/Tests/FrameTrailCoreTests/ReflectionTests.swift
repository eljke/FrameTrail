import Foundation
import XCTest
@testable import FrameTrailCore

final class ReflectionTests: XCTestCase {
    func testSeasonReviewExcludesUnwatchedAndOtherSeasonSources() {
        let title = MediaTitle(id: "show", title: "Show", kind: .series, provider: "local", providerID: "show")
        let episodes = [Episode(id: "e1", season: 1, number: 1, name: "First", summary: "Allowed events"), Episode(id: "e2", season: 1, number: 2, name: "Second", summary: "Future events"), Episode(id: "e3", season: 2, number: 1, name: "Third", summary: "Other season")]
        let context = SpoilerContextBuilder.forReview(title: title, episodes: episodes, progress: WatchProgress(watchedEpisodeIDs: ["e1", "e3"]), facts: [], episodeID: nil, seasonNumber: 1)
        XCTAssertEqual(context.allowedEpisodeIDs, ["e1"])
        XCTAssertTrue(context.text.contains("Allowed events"))
        XCTAssertFalse(context.text.contains("Future events"))
        XCTAssertFalse(context.text.contains("Other season"))
    }

    func testSeasonRatingDoesNotReplaceOverallOrEpisodeRating() throws {
        let records = [Reflection(titleID: "show", rating: 7), Reflection(titleID: "show", rating: 9, seasonNumber: 1), Reflection(titleID: "show", rating: 4, episodeID: "e1", episodeSeason: 1, episodeNumber: 1)]
        let restored = try JSONDecoder().decode([Reflection].self, from: JSONEncoder().encode(records))
        XCTAssertEqual(Reflection.latest(in: restored)?.rating, 7)
        XCTAssertEqual(Reflection.latest(in: restored, seasonNumber: 1)?.rating, 9)
        XCTAssertEqual(Reflection.latest(in: restored, episodeID: "e1")?.rating, 4)
        XCTAssertNil(Reflection.latest(in: restored, seasonNumber: 2))
    }

    func testOldArchivesRemainReadable() throws {
        let data = Data("{\"id\":\"11111111-2222-3333-4444-555555555555\",\"titleID\":\"film\",\"summary\":\"Remember this\",\"liked\":[\"Acting\"],\"questions\":[],\"rating\":8,\"createdAt\":0}".utf8)
        let review = try JSONDecoder().decode(Reflection.self, from: data)
        XCTAssertEqual(review.rating, 8)
        XCTAssertEqual(review.liked, ["Acting"])
        XCTAssertTrue(review.disliked.isEmpty)
        XCTAssertNil(review.episodeID)
    }

    func testEpisodeReviewCannotReadAnotherWatchedEpisode() {
        let title = MediaTitle(id: "show", title: "Show", kind: .series, provider: "test", providerID: "show")
        let episodes = [Episode(id: "e1", season: 1, number: 1, name: "First", summary: "First events."), Episode(id: "e2", season: 1, number: 2, name: "Second", summary: "Later events.")]
        let progress = WatchProgress(watchedEpisodeIDs: ["e1", "e2"])
        let packet = SpoilerContextBuilder.forReview(title: title, episodes: episodes, progress: progress, facts: [], episodeID: "e1")
        XCTAssertEqual(packet.allowedEpisodeIDs, ["e1"])
        XCTAssertFalse(packet.text.contains("Later events"))
        let unwatched = SpoilerContextBuilder.forReview(title: title, episodes: episodes, progress: WatchProgress(), facts: [], episodeID: "e1")
        XCTAssertFalse(unwatched.hasEvidence)
    }

    func testCompilationUsesLatestNotesOnlyForWatchedEpisodes() {
        let records = [
            Reflection(titleID: "show", liked: ["Old opinion"], rating: 3, createdAt: Date(timeIntervalSince1970: 1), episodeID: "e1", episodeSeason: 1, episodeNumber: 1),
            Reflection(titleID: "show", liked: ["Great acting"], rating: 9, createdAt: Date(timeIntervalSince1970: 2), disliked: ["Slow pacing"], episodeID: "e1", episodeSeason: 1, episodeNumber: 1),
            Reflection(titleID: "show", summary: "FUTURE SPOILER", episodeID: "e2", episodeSeason: 1, episodeNumber: 2),
            Reflection(titleID: "show", summary: "WHOLE SERIES SPOILER")
        ]
        let plan = ReflectionCompilation(records: records, watchedEpisodeIDs: ["e1"])
        XCTAssertEqual(plan.episodeCount, 1)
        let text = plan.batches.joined()
        XCTAssertTrue(text.contains("Great acting"))
        XCTAssertTrue(text.contains("Slow pacing"))
        XCTAssertFalse(text.contains("Old opinion"))
        XCTAssertFalse(text.contains("SPOILER"))
    }

    func testCompilationBatchesEveryEpisodeWithinContextBudget() {
        let records = (1...120).map { number in
            Reflection(titleID: "show", summary: String(repeating: "Long note ", count: 100), liked: ["Good acting"], rating: 7, episodeID: "e\(number)", episodeSeason: 1, episodeNumber: number)
        }
        let plan = ReflectionCompilation(records: records, watchedEpisodeIDs: Set(records.compactMap(\.episodeID)))
        XCTAssertEqual(plan.episodeCount, 120)
        XCTAssertTrue(plan.batches.count > 1)
        XCTAssertTrue(plan.shortened)
        XCTAssertTrue(plan.batches.allSatisfy { $0.count <= 5_000 })
        XCTAssertTrue(plan.batches.joined().contains("S1 E120,"))
    }

    func testReviewPassagesCoverTheEndingOfLongPlots() throws {
        let title = MediaTitle(id: "film", title: "Film", kind: .movie, provider: "local", providerID: "film")
        let text = (1...50).map { "Event \($0) changes the characters and their plans." }.joined(separator: " ") + " The final revelation changes the meaning of their reunion."
        let packet = SpoilerContextBuilder.forReview(title: title, episodes: [], progress: WatchProgress(finished: true), facts: [StoryFact(id: "plot", text: text, kind: "plot", titleID: title.id)], episodeID: nil)
        let passages = ReviewPassages.candidates(in: packet)
        XCTAssertEqual(passages.count, 12)
        XCTAssertTrue(passages.last?.quote.contains("final revelation") == true)
        XCTAssertTrue(passages.allSatisfy { text.contains($0.quote) })
    }

    func testPreparedAnswersCannotInventPassagesOrUseOtherEpisodes() throws {
        let title = MediaTitle(id: "show", title: "Show", kind: .series, provider: "test", providerID: "show")
        let first = Episode(id: "e1", season: 1, number: 1, name: "First", summary: "Walter avoids a confrontation and returns home safely.")
        let second = Episode(id: "e2", season: 1, number: 2, name: "Second", summary: "FUTURE EVENT which must not appear in these answers.")
        let packet = SpoilerContextBuilder.forReview(title: title, episodes: [first, second], progress: WatchProgress(watchedEpisodeIDs: ["e1", "e2"]), facts: [], episodeID: "e1")
        let candidates = ReviewPassages.candidates(in: packet)
        let passage = try XCTUnwrap(candidates.first)
        let choice = try XCTUnwrap(ReviewPassages.choice(passageID: passage.id, aspect: .characters, candidates: candidates))
        XCTAssertTrue(first.summary.contains(choice.sourceQuote))
        XCTAssertEqual(choice.episodeID, "e1")
        XCTAssertFalse(choice.text.contains("FUTURE"))
        XCTAssertNil(ReviewPassages.choice(passageID: "invented-event", aspect: .story, candidates: candidates))
    }
}
