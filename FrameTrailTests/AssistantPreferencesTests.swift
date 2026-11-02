import Foundation
import FrameTrailCore
import XCTest
@testable import FrameTrail

@MainActor
final class AssistantPreferencesTests: XCTestCase {
    func testMixedLanguageQuestionStillRequiresTranslation() {
        XCTAssertTrue(LocalTranslationService.needsRussianTranslation("Explain the scene where Уолтер meets Jesse and then leaves the house."))
        XCTAssertFalse(LocalTranslationService.needsRussianTranslation("Explain Walter's choice."))
    }

    func testAnswerLanguageIsIndependentFromInterface() {
        let defaults = UserDefaults.standard
        let keys = ["app.language", "assistant.locale", "assistant.answer-language"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let model = AppModel()
        model.localeIdentifier = "ru_RU"
        model.answerLanguage = "en"
        XCTAssertEqual(model.answerLocaleIdentifier, "en_US")
        XCTAssertEqual(L10n.language, "ru")
        model.answerLanguage = "auto"
        XCTAssertEqual(model.answerLocaleIdentifier, "ru_RU")
    }

    func testHiddenRecommendationPersistsAndTravelsThroughCloudPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        store.switchAccount("supabase:test")
        let title = MediaTitle(id: "movie", title: "Movie", kind: .movie, provider: "TMDB", providerID: "1")
        store.hideRecommendation(title)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.visibleEntries.isEmpty)
        XCTAssertEqual(store.hiddenRecommendations.map(\.id), [title.id])
        XCTAssertEqual(store.cloudItems().first?.recommendationHidden, true)
        store.clearDownloadedMaterials()
        XCTAssertEqual(store.hiddenRecommendations.count, 1)
        let restored = LibraryStore(directory: directory)
        restored.switchAccount("supabase:test")
        XCTAssertEqual(restored.hiddenRecommendations.count, 1)
        restored.restoreRecommendation(title.id)
        XCTAssertTrue(restored.hiddenRecommendations.isEmpty)
        XCTAssertTrue(restored.visibleEntries.isEmpty)
        store.switchAccount("guest")
        XCTAssertTrue(store.hiddenRecommendations.isEmpty)
    }

    func testRestoringSyncedHiddenWatchlistItemKeepsItsNotes() throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let source = LibraryStore(directory: first)
        source.switchAccount("supabase:test")
        let title = MediaTitle(id: "movie", title: "Movie", kind: .movie, provider: "TMDB", providerID: "1")
        var entry = LibraryEntry(title: title)
        entry.reflections = [Reflection(titleID: title.id, summary: "A note to keep")]
        source.update(entry)
        source.hideRecommendation(title)
        let payload = try XCTUnwrap(source.cloudItems().first)
        let restored = LibraryStore(directory: second)
        restored.switchAccount("supabase:test")
        try restored.applyCloudRecord(CloudLibraryRecord(mediaID: title.id, payload: payload, revision: 1, deleted: false))
        restored.restoreRecommendation(title.id)
        XCTAssertEqual(restored.visibleEntries.map(\.id), [title.id])
        XCTAssertEqual(restored.entry(for: title.id)?.reflections, entry.reflections)
        XCTAssertEqual(LibraryStore(directory: second).activeAccountID, "guest")
    }

    func testWatchingHiddenDiscoveryKeepsNewProgressAndNotes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        let title = MediaTitle(id: "movie", title: "Movie", kind: .movie, provider: "TMDB", providerID: "1")
        store.hideRecommendation(title)
        var watched = try XCTUnwrap(store.entry(for: title.id))
        watched.progress.finished = true
        watched.reflections = [Reflection(titleID: title.id, summary: "Changed my mind", rating: 9)]
        store.update(watched)
        XCTAssertEqual(store.visibleEntries.map(\.id), [title.id])
        store.restoreRecommendation(title.id)
        XCTAssertEqual(store.entry(for: title.id)?.reflections, watched.reflections)
        XCTAssertEqual(LibraryStore(directory: directory).entry(for: title.id)?.progress.finished, true)
    }
}
