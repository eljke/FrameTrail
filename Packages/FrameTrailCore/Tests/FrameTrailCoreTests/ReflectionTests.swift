import Foundation
import XCTest
@testable import FrameTrailCore

final class ReflectionTests: XCTestCase {
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
}
