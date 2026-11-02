import XCTest
@testable import FrameTrailCore

final class RecommendationPoolTests: XCTestCase {
    func testQualityGateRejectsHypeSmallSamplesAndLibraryTitles() {
        func candidate(_ id: String, rating: Double, votes: Int, popularity: Double) -> RecommendationCandidate {
            RecommendationCandidate(title: MediaTitle(id: id, title: id, kind: .movie, provider: "TMDB", providerID: id), rating: rating, votes: votes, popularity: popularity)
        }
        let good = candidate("good", rating: 8.2, votes: 4000, popularity: 20)
        let pool = RecommendationPool.ranked([candidate("viral", rating: 4, votes: 8000, popularity: 9000), candidate("tiny", rating: 10, votes: 3, popularity: 100), candidate("saved", rating: 9, votes: 9000, popularity: 90), good, good], excluding: ["saved"])
        XCTAssertEqual(pool.map(\.title.id), ["good"])
    }
}
