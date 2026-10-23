import Foundation
import XCTest
@testable import FrameTrailCore

final class EpisodeRatingTests: XCTestCase {
    func testBulkRatingPreservesNotesAndExistingScores() {
        let episodes = (1...3).map { Episode(id: "e\($0)", season: 1, number: $0, name: "Episode") }
        let existing = Reflection(titleID: "show", liked: ["Acting"], rating: 3, episodeID: "e1", episodeSeason: 1, episodeNumber: 1)
        let unrated = Reflection(titleID: "show", summary: "My notes", episodeID: "e2", episodeSeason: 1, episodeNumber: 2)
        let plan = EpisodeRatingPlan(titleID: "show", episodes: episodes, watchedEpisodeIDs: ["e1", "e2"], records: [existing, unrated], rating: 8)
        XCTAssertEqual(plan.changedCount, 1)
        XCTAssertEqual(Reflection.latest(in: plan.records, episodeID: "e1"), existing)
        XCTAssertEqual(Reflection.latest(in: plan.records, episodeID: "e2")?.summary, "My notes")
        XCTAssertEqual(Reflection.latest(in: plan.records, episodeID: "e2")?.rating, 8)
        XCTAssertNil(Reflection.latest(in: plan.records, episodeID: "e3"))
    }

    func testBulkOverwriteStaysWithinSeasonAndIsIdempotent() {
        let episodes = [Episode(id: "e1", season: 1, number: 1, name: "First"), Episode(id: "e2", season: 2, number: 1, name: "Second")]
        let record = Reflection(titleID: "show", liked: ["Keep this"], rating: 2, episodeID: "e1", episodeSeason: 1, episodeNumber: 1)
        let first = EpisodeRatingPlan(titleID: "show", episodes: episodes, watchedEpisodeIDs: ["e1", "e2"], records: [record], rating: 9, season: 1, overwrite: true)
        XCTAssertEqual(first.changedCount, 1)
        XCTAssertEqual(first.records.count, 1)
        XCTAssertEqual(first.records[0].liked, ["Keep this"])
        let second = EpisodeRatingPlan(titleID: "show", episodes: episodes, watchedEpisodeIDs: ["e1", "e2"], records: first.records, rating: 9, season: 1, overwrite: true)
        XCTAssertEqual(second.changedCount, 0)
        XCTAssertEqual(second.records, first.records)
    }
}
