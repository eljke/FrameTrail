import XCTest
@testable import FrameTrailCore

final class StoryCheckpointTests: XCTestCase {
    private let title = MediaTitle(id: "show", title: "Test", kind: .series, provider: "test", providerID: "show")
    private let episodes = [Episode(id: "e1", season: 1, number: 1, name: "First", summary: "Arrival"), Episode(id: "e2", season: 1, number: 2, name: "Second", summary: "Secret"), Episode(id: "e3", season: 2, number: 1, name: "Third", summary: "Ending")]

    func testRewindExcludesLaterWatchedEpisodesAndReviews() {
        let records = [Reflection(titleID: "show", summary: "My first impression", rating: 8, episodeID: "e1"), Reflection(titleID: "show", summary: "The ending", rating: 2, episodeID: "e3"), Reflection(titleID: "other", summary: "Foreign", episodeID: "e1")]
        let checkpoint = StoryCheckpoint(title: title, episodes: Array(episodes.reversed()), progress: WatchProgress(finished: true, watchedEpisodeIDs: ["e1", "e3"]), facts: [StoryFact(id: "future", text: "Ending", episodeID: "e3")], records: records, through: "e1")
        XCTAssertEqual(checkpoint.episodes.map(\.id), ["e1"])
        XCTAssertEqual(checkpoint.context.allowedEpisodeIDs, ["e1"])
        XCTAssertFalse(checkpoint.context.text.contains("Ending"))
        XCTAssertEqual(checkpoint.reviews.map(\.summary), ["My first impression"])
    }

    func testUnwatchedCheckpointFailsClosed() {
        let checkpoint = StoryCheckpoint(title: title, episodes: episodes, progress: WatchProgress(watchedEpisodeIDs: ["e1"]), facts: [], records: [], through: "e2")
        XCTAssertTrue(checkpoint.episodes.isEmpty)
        XCTAssertFalse(checkpoint.context.hasEvidence)
    }

    func testGapsAndClearedRatingsArePreserved() {
        let old = Reflection(titleID: "show", summary: "Old", rating: 9, createdAt: .distantPast, episodeID: "e1")
        let cleared = Reflection(titleID: "show", createdAt: .distantFuture, episodeID: "e1")
        let checkpoint = StoryCheckpoint(title: title, episodes: episodes, progress: WatchProgress(watchedEpisodeIDs: ["e1", "e3"]), facts: [], records: [old, cleared], through: "e3")
        XCTAssertEqual(checkpoint.episodes.map(\.id), ["e1", "e3"])
        XCTAssertTrue(checkpoint.reviews.isEmpty)
        XCTAssertFalse(checkpoint.context.allowedEpisodeIDs.contains("e2"))
    }
}
