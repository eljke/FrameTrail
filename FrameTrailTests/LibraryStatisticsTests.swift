import Foundation
import FrameTrailCore
import XCTest
@testable import FrameTrail

final class LibraryStatisticsTests: XCTestCase {
    func testEmptyLibraryHasNoInventedAverage() {
        let statistics = LibraryStatistics(entries: [])

        XCTAssertEqual(statistics.titleCount, 0)
        XCTAssertEqual(statistics.completedTitleCount, 0)
        XCTAssertEqual(statistics.watchedEpisodeCount, 0)
        XCTAssertEqual(statistics.reflectionCount, 0)
        XCTAssertEqual(statistics.movieCount, 0)
        XCTAssertEqual(statistics.seriesCount, 0)
        XCTAssertEqual(statistics.ratedReflectionCount, 0)
        XCTAssertNil(statistics.averageRating)
        XCTAssertTrue(statistics.ratingDistribution.allSatisfy { $0.count == 0 })
    }

    func testCountsUseSavedProgressEvenWithoutCachedEpisodes() {
        var movie = entry("film", kind: .movie)
        movie.progress.finished = true
        var firstShow = entry("show-1", kind: .series)
        firstShow.progress.watchedEpisodeIDs = ["episode-1", "episode-2"]
        var secondShow = entry("show-2", kind: .series)
        secondShow.progress.finished = true
        secondShow.progress.watchedEpisodeIDs = ["episode-1"]
        secondShow.reflections = [Reflection(titleID: "show-2", summary: "A good ending.")]

        let statistics = LibraryStatistics(entries: [movie, firstShow, secondShow])

        XCTAssertEqual(statistics.titleCount, 3)
        XCTAssertEqual(statistics.completedTitleCount, 2)
        XCTAssertEqual(statistics.watchedEpisodeCount, 3)
        XCTAssertEqual(statistics.movieCount, 1)
        XCTAssertEqual(statistics.seriesCount, 2)
        XCTAssertEqual(statistics.reflectionCount, 1)
        XCTAssertNil(statistics.averageRating)
    }

    func testAverageAndDistributionUseRatedRecordsRatherThanTitles() throws {
        var movie = entry("film", kind: .movie)
        movie.reflections = [
            Reflection(titleID: "film", summary: "First viewing.", rating: 6),
            Reflection(titleID: "film", summary: "Second viewing.", rating: 9),
            Reflection(titleID: "film", summary: "A thought without a rating.")
        ]
        var series = entry("show", kind: .series)
        series.reflections = [Reflection(titleID: "show", summary: "The final season.", rating: 9)]

        let statistics = LibraryStatistics(entries: [movie, series])

        XCTAssertEqual(statistics.reflectionCount, 4)
        XCTAssertEqual(statistics.ratedReflectionCount, 3)
        XCTAssertEqual(try XCTUnwrap(statistics.averageRating), 8, accuracy: 0.000_001)
        XCTAssertEqual(statistics.ratingDistribution.first { $0.rating == 6 }?.count, 1)
        XCTAssertEqual(statistics.ratingDistribution.first { $0.rating == 9 }?.count, 2)
        XCTAssertEqual(statistics.ratingDistribution.reduce(0) { $0 + $1.count }, 3)
    }

    private func entry(_ id: String, kind: MediaKind) -> LibraryEntry {
        LibraryEntry(title: MediaTitle(id: id, title: id, kind: kind, provider: "test", providerID: id))
    }
}
