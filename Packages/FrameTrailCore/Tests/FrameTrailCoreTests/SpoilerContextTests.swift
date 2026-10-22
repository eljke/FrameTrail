import Foundation
import XCTest
@testable import FrameTrailCore

final class SpoilerContextTests: XCTestCase {
    func testFutureAndGlobalPlotAreExcluded() {
        let title = series(overview: "The detective is secretly the murderer.")
        let episodes = [
            episode("first", number: 1, summary: "Detective Mira arrives."),
            episode("last", number: 2, summary: "Mira confesses the murder.")
        ]
        let context = SpoilerContextBuilder.build(
            title: title,
            episodes: episodes,
            progress: WatchProgress(watchedEpisodeIDs: ["first"], currentSeason: 1, currentEpisode: 2),
            facts: [
                StoryFact(id: "safe", text: "Mira interviews a witness.", episodeID: "first"),
                StoryFact(id: "future", text: "Mira is the killer.", episodeID: "last"),
                StoryFact(id: "unscoped", text: "Everyone dies in the finale.")
            ],
            question: "Who is Mira?"
        )

        XCTAssertEqual(context.allowedEpisodeIDs, ["first"])
        XCTAssertTrue(context.text.contains("interviews a witness"))
        XCTAssertFalse(context.text.contains("killer"))
        XCTAssertFalse(context.text.contains("murder"))
        XCTAssertFalse(context.text.contains("Everyone dies"))
        XCTAssertEqual(Set(context.evidence.map(\.id)), ["safe", "episode:first:summary"])
    }

    func testCompletionUsesIDsRatherThanEpisodeOrderOrCurrentNumber() {
        let context = SpoilerContextBuilder.build(
            title: series(),
            episodes: [
                episode("third", number: 3, summary: "Third event."),
                episode("first", number: 1, summary: "First event."),
                episode("second", number: 2, summary: "Second event.")
            ],
            progress: WatchProgress(
                finished: true,
                watchedEpisodeIDs: ["second", "not-in-this-show"],
                currentSeason: 20,
                currentEpisode: 99
            ),
            facts: [],
            question: "recap"
        )

        XCTAssertEqual(context.allowedEpisodeIDs, ["second"])
        XCTAssertEqual(context.evidence.map(\.episodeID), ["second"])
        XCTAssertFalse(context.text.contains("First event"))
        XCTAssertFalse(context.text.contains("Third event"))
    }

    func testUnfinishedMovieHasNoPlot() {
        let context = SpoilerContextBuilder.build(
            title: movie(overview: "The daughter inherits the kingdom."),
            episodes: [],
            progress: WatchProgress(),
            facts: [StoryFact(id: "ending", text: "The king dies.")],
            question: "Explain the ending"
        )

        XCTAssertFalse(context.hasEvidence)
        XCTAssertFalse(context.text.contains("inherits"))
        XCTAssertFalse(context.text.contains("king dies"))
    }

    func testFinishingMovieDoesNotUnlockSequel() {
        let context = SpoilerContextBuilder.build(
            title: movie(overview: "The first journey ends at home."),
            episodes: [episode("sequel-scene", number: 1, summary: "Home is destroyed.")],
            progress: WatchProgress(finished: true, watchedEpisodeIDs: ["sequel-scene"]),
            facts: [
                StoryFact(id: "first-ending", text: "Ada returns home.", titleID: "movie:1"),
                StoryFact(id: "sequel-ending", text: "Ada dies in the sequel.", titleID: "movie:2"),
                StoryFact(id: "episode-ending", text: "Home is destroyed.", episodeID: "sequel-scene")
            ],
            question: "What happened to Ada?"
        )

        XCTAssertTrue(context.text.contains("Ada returns home"))
        XCTAssertTrue(context.text.contains("journey ends"))
        XCTAssertFalse(context.text.contains("Ada dies"))
        XCTAssertFalse(context.text.contains("Home is destroyed"))
        XCTAssertTrue(context.allowedEpisodeIDs.isEmpty)
    }

    func testNoEvidenceIsExplicit() {
        let context = SpoilerContextBuilder.build(
            title: series(), episodes: [episode("empty", number: 1, summary: "")],
            progress: WatchProgress(watchedEpisodeIDs: ["empty"]), facts: [], question: "Who is her father?"
        )

        XCTAssertTrue(context.evidence.isEmpty)
        XCTAssertTrue(context.coverage.contains("Нет доступных материалов"))
    }

    func testRetrievalPrioritizesQuestionWithinBudget() {
        let context = SpoilerContextBuilder.build(
            title: movie(), episodes: [], progress: WatchProgress(finished: true),
            facts: [
                StoryFact(id: "landscape", text: String(repeating: "The landscape is green. ", count: 100)),
                StoryFact(id: "compass", text: "Mira follows the broken compass to the lighthouse.")
            ],
            question: "Where does the compass lead?",
            maxCharacters: 210
        )

        XCTAssertEqual(context.evidence.first?.id, "compass")
        XCTAssertTrue(context.text.contains("lighthouse"))
        XCTAssertLessThanOrEqual(context.text.count, 210)
        XCTAssertTrue(context.coverage.contains("Частичный"))
    }

    func testEvidenceMatchesTruncatedContext() {
        let context = SpoilerContextBuilder.build(
            title: movie(), episodes: [], progress: WatchProgress(finished: true),
            facts: [StoryFact(id: "long", text: String(repeating: "🌍", count: 300))],
            question: "", maxCharacters: 170
        )

        XCTAssertLessThanOrEqual(context.text.count, 170)
        XCTAssertEqual(context.evidence.count, 1)
        XCTAssertTrue(context.text.hasSuffix(context.evidence[0].text))
        XCTAssertLessThan(context.evidence[0].text.count, 300)
    }

    func testZeroBudgetDoesNotReturnEvidence() {
        let context = SpoilerContextBuilder.build(
            title: movie(overview: "Plot"), episodes: [], progress: WatchProgress(finished: true),
            facts: [StoryFact(id: "a", text: "Fact")], question: "", maxCharacters: 0
        )

        XCTAssertTrue(context.text.isEmpty)
        XCTAssertTrue(context.evidence.isEmpty)
    }

    func testRepeatedSourcesAreDeduplicated() {
        let fact = StoryFact(id: "same", text: "One event.", episodeID: "first")
        let context = SpoilerContextBuilder.build(
            title: series(), episodes: [episode("first", number: 1, summary: "")],
            progress: WatchProgress(watchedEpisodeIDs: ["first"]), facts: [fact, fact], question: ""
        )

        XCTAssertEqual(context.evidence.count, 1)
    }

    private func movie(overview: String = "") -> MediaTitle {
        MediaTitle(id: "movie:1", title: "A Journey", kind: .movie, overview: overview, provider: "test", providerID: "1")
    }

    private func series(overview: String = "") -> MediaTitle {
        MediaTitle(id: "series:1", title: "Mira", kind: .series, overview: overview, provider: "test", providerID: "1")
    }

    private func episode(_ id: String, number: Int, summary: String) -> Episode {
        Episode(id: id, season: 1, number: number, name: "Episode \(number)", summary: summary)
    }
}
