import XCTest
@testable import FrameTrailCore

final class TastePortraitTests: XCTestCase {
    func testOnlyEligibleLatestPersonalReviewsBecomeEvidence() {
        let title = MediaTitle(id: "show", title: "Example", kind: .series, provider: "test", providerID: "1")
        let old = Reflection(titleID: "show", summary: "Old opinion", createdAt: .distantPast, episodeID: "first")
        let cleared = Reflection(titleID: "show", createdAt: .distantFuture, episodeID: "first")
        let sample = TasteSample(title: title, progress: WatchProgress(watchedEpisodeIDs: ["first", "second"]), reviews: [old, cleared, Reflection(titleID: "show", summary: "The difficult choices worked", rating: 9, episodeID: "second"), Reflection(titleID: "show", summary: "Future secret", episodeID: "last"), Reflection(titleID: "show", summary: "Global ending"), Reflection(titleID: "other", summary: "Foreign", episodeID: "second")])
        let portrait = TastePortrait(samples: [sample])
        XCTAssertEqual(portrait.context.evidence.count, 1)
        XCTAssertTrue(portrait.context.evidence[0].text.contains("difficult choices"))
        XCTAssertFalse(portrait.context.text.contains("Future secret"))
        XCTAssertFalse(portrait.context.text.contains("Old opinion"))
        XCTAssertFalse(portrait.context.text.contains("Global ending"))
    }

    func testCompletedMovieNotesAreBoundedAndNeverIncludeCatalogPlot() {
        let title = MediaTitle(id: "movie", title: "Example", kind: .movie, overview: "Catalog spoiler", provider: "test", providerID: "1")
        let review = Reflection(titleID: "movie", summary: String(repeating: "Personal note ", count: 2000), rating: 8)
        let portrait = TastePortrait(samples: [TasteSample(title: title, progress: WatchProgress(finished: true), reviews: [review])])
        XCTAssertEqual(portrait.context.evidence.count, 1)
        XCTAssertLessThanOrEqual(portrait.context.evidence[0].text.count, 1200)
        XCTAssertFalse(portrait.context.text.contains("Catalog spoiler"))
        XCTAssertFalse(TastePortrait(samples: [TasteSample(title: title, progress: WatchProgress(), reviews: [review])]).context.hasEvidence)
    }
}
