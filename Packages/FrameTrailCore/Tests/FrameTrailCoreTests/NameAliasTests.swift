import XCTest
import Foundation
@testable import FrameTrailCore

final class NameAliasTests: XCTestCase {
    func testSuggestedSpellingsMustExistInPermittedRussianSource() {
        let proposals = [NameSpellingSuggestion(nameID: "N1", russian: "Уолтер"), NameSpellingSuggestion(nameID: "N2", russian: "Джесси"), NameSpellingSuggestion(nameID: "N3", russian: "Уолтер"), NameSpellingSuggestion(nameID: "N1", russian: "Вальт")]
        let aliases = NameAlias.suggested(proposals, originals: ["Walter", "Jesse"], russianSource: "Уолтер возвращается домой. О Джесси здесь не сказано.")
        XCTAssertEqual(aliases, [NameAlias(original: "Walter", russian: "Уолтер"), NameAlias(original: "Jesse", russian: "Джесси")])
        XCTAssertTrue(NameAlias.suggested([NameSpellingSuggestion(nameID: "N1", russian: "Уолт")], originals: ["Walter"], russianSource: "Уолтер").isEmpty)
    }

    func testAliasesAndSeasonReviewRoundTripTogether() throws {
        let title = MediaTitle(id: "show", title: "Show", kind: .series, provider: "local", providerID: "show")
        let item = CloudLibraryItem(title: title, progress: WatchProgress(), reflections: [Reflection(titleID: title.id, rating: 8, seasonNumber: 1)], nameAliases: [NameAlias(original: "Walt", russian: "Уолт")])
        let restored = try JSONDecoder().decode(CloudLibraryItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored, item)
    }

    func testNamesUseConfirmedAliasesAndOriginalFallback() {
        let protected = ProtectedTranslationText(text: "Walt meets Walter White at the DEA. Walt leaves.", names: ["Walt": "Уолт", "Walter White": "Уолтер Уайт", "DEA": "DEA"])
        XCTAssertFalse(protected.text.contains("Walter White"))
        XCTAssertEqual(protected.restored(protected.text), "Уолт meets Уолтер Уайт at the DEA. Уолт leaves.")
    }

    func testMissingOrDuplicatedNameTokensAreRejected() {
        let protected = ProtectedTranslationText(text: "Walt returns.", names: ["Walt": "Уолт"])
        XCTAssertNil(protected.restored("Something else."))
        XCTAssertNil(protected.restored(protected.text + protected.text))
    }

    func testAliasesDoNotReplacePartsOfOtherNames() {
        let protected = ProtectedTranslationText(text: "Walter meets Walt.", names: ["Walt": "Уолт"])
        XCTAssertEqual(protected.restored(protected.text), "Walter meets Уолт.")
    }
}
