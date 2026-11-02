import XCTest
@testable import FrameTrailCore

final class ViewingAssistantTests: XCTestCase {
    func testProtectionPreservesRepeatedNamesAndRejectsLostRanges() {
        let plan = TranslationProtection(text: "Уолтер встретил Jesse. Уолтер позвонил DEA.", names: ["Уолтер": "Walter", "Jesse": "Jesse", "DEA": "DEA"])
        XCTAssertEqual(plan.segments.filter(\.isProtected).map(\.text), ["Walter", "Jesse", "Walter", "DEA"])
        XCTAssertTrue(plan.accepts("Walter met Jesse. Walter called DEA."))
        XCTAssertFalse(plan.accepts("Walter met Jesse. He called DEA."))
        XCTAssertFalse(plan.accepts("Вальт встретил Джесси."))
    }

    func testProtectionUsesLongestWholeName() {
        let plan = TranslationProtection(text: "Walter White meets Walterson and Walt.", names: ["Walter White": "Уолтер Уайт", "Walter": "Уолтер", "Walt": "Уолт"])
        XCTAssertEqual(plan.segments.filter(\.isProtected).map(\.text), ["Уолтер Уайт", "Уолт"])
        XCTAssertTrue(plan.segments.contains { $0.text.contains("Walterson") && !$0.isProtected })
    }

    func testFullAndShortProtectedNamesDoNotCountEachOtherTwice() {
        let plan = TranslationProtection(text: "Walter White greets Walter.", names: ["Walter White": "Уолтер Уайт", "Walter": "Уолтер"])
        XCTAssertTrue(plan.accepts("Уолтер Уайт приветствует Уолтер."))
        XCTAssertFalse(plan.accepts("Уолтер Уайт приветствует Уолтер. Уолтер."))
    }

    func testRecommendationBriefKeepsHardConditionsAndRejectsUnknownRuntime() {
        let film = MediaTitle(id: "short", title: "Short", kind: .movie, provider: "tmdb", providerID: "1")
        let short = RecommendationCandidate(title: film, rating: 8, votes: 1000, popularity: 10, runtimeMinutes: 95)
        let unknown = RecommendationCandidate(title: film, rating: 8, votes: 1000, popularity: 10)
        let brief = RecommendationBrief(kind: .movie, maximumMinutes: 100, request: "Something tense")
        XCTAssertTrue(brief.accepts(short))
        XCTAssertFalse(brief.accepts(unknown))
        XCTAssertFalse(RecommendationBrief(kind: .series, maximumMinutes: nil, request: "").accepts(short))
    }

    func testRecommendationsRecognizeWatchedTitlesAcrossProvidersWithoutHidingRemakes() {
        let watched = MediaTitle(id: "tvmaze:169", title: "Breaking Bad", kind: .series, year: 2008, provider: "TVmaze", providerID: "169")
        let same = MediaTitle(id: "tmdb:tv:1", title: "Во все тяжкие", originalTitle: "Breaking Bad", kind: .series, year: 2008, provider: "TMDB", providerID: "1")
        let remake = MediaTitle(id: "tmdb:tv:2", title: "Breaking Bad", kind: .series, year: 2030, provider: "TMDB", providerID: "2")
        let candidates = [same, remake].map { RecommendationCandidate(title: $0, rating: 8, votes: 1000, popularity: 10) }
        XCTAssertEqual(RecommendationPool.ranked(candidates, excluding: [], excludingTitles: [watched]).map(\.id), [remake.id])
    }

    func testAtlasRejectsInventedNamesAndEvidenceOutsideCheckpoint() {
        let fact = StoryFact(id: "first", text: "Walter calls Jesse to ask for help.", episodeID: "e1")
        let context = GroundedContext(text: "", evidence: [fact], coverage: "", allowedEpisodeIDs: ["e1"])
        let atlas = StoryAtlas(context: context, mentions: [
            CharacterMention(name: "Walter", sourceID: "first", quote: "Walter calls Jesse to ask for help."),
            CharacterMention(name: "Jesse", sourceID: "first", quote: "Walter calls Jesse to ask for help."),
            CharacterMention(name: "Secret", sourceID: "future", quote: "Secret appears later."),
            CharacterMention(name: "Invented", sourceID: "first", quote: "Walter calls Jesse to ask for help.")
        ])
        XCTAssertEqual(atlas.people.map(\.name), ["Jesse", "Walter"])
        XCTAssertEqual(atlas.people.first?.sources.map(\.id), ["first"])
        XCTAssertEqual(atlas.companions(of: "Walter"), ["Jesse"])
    }

    func testMemorySearchKeepsLatestWatchedOpinionsAndNeverCatalogPlot() {
        let title = MediaTitle(id: "show", title: "Show", kind: .series, overview: "Catalog secret", provider: "test", providerID: "1")
        let sample = TasteSample(title: title, progress: WatchProgress(watchedEpisodeIDs: ["e1"]), reviews: [
            Reflection(titleID: "show", summary: "Great ending", createdAt: .distantPast, episodeID: "e1"),
            Reflection(titleID: "show", summary: "Slow pacing", createdAt: .distantFuture, episodeID: "e1"),
            Reflection(titleID: "show", summary: "Future ending", episodeID: "e2")
        ])
        let memory = ViewingMemory.context(samples: [sample], query: "pacing")
        XCTAssertEqual(memory.evidence.count, 1)
        XCTAssertTrue(memory.evidence[0].text.contains("Slow pacing"))
        XCTAssertFalse(memory.text.contains("Great ending"))
        XCTAssertFalse(memory.text.contains("Future ending"))
        XCTAssertFalse(memory.text.contains("Catalog secret"))
        XCTAssertFalse(ViewingMemory.context(samples: [sample], query: "unrelated").hasEvidence)
    }
}
