import Foundation
import XCTest
@testable import FrameTrailCore

final class DomainPersistenceTests: XCTestCase {
    func testProgressRoundTripPreservesSkippedEpisodes() throws {
        let progress = WatchProgress(finished: false, watchedEpisodeIDs: ["s1e1", "s1e3"], currentSeason: 1, currentEpisode: 4)

        let decoded = try JSONDecoder().decode(WatchProgress.self, from: JSONEncoder().encode(progress))

        XCTAssertEqual(decoded, progress)
        XCTAssertFalse(decoded.watchedEpisodeIDs.contains("s1e2"))
    }

    func testReflectionRoundTripPreservesPersonalNotes() throws {
        let reflection = Reflection(
            titleID: "movie:1", summary: "A hopeful ending.", liked: ["The soundtrack"],
            questions: ["Did she forgive him?"], rating: 8
        )

        let decoded = try JSONDecoder().decode(Reflection.self, from: JSONEncoder().encode(reflection))

        XCTAssertEqual(decoded, reflection)
    }
}
