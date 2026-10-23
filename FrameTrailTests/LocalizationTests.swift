import Foundation
import XCTest
@testable import FrameTrail

final class LocalizationTests: XCTestCase {
    func testLanguageSwitchResolvesResourcesAndInterpolatedValues() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "app.language")
        defer { defaults.set(previous, forKey: "app.language") }
        defaults.set("en", forKey: "app.language")
        XCTAssertEqual(L10n.text("Библиотека"), "Library")
        XCTAssertEqual(L10n.text("Сезон %@ · Серия %@", "2", "4"), "Season 2 · Episode 4")
        XCTAssertEqual(L10n.error(URLError(.timedOut)), "The server took too long to respond. Try again.")
        XCTAssertEqual(L10n.text("Нет оценки"), "Нет оценки")
        defaults.set("ru", forKey: "app.language")
        XCTAssertEqual(L10n.text("Библиотека"), "Библиотека")
        XCTAssertEqual(L10n.text("Сезон %@ · Серия %@", "2", "4"), "Сезон 2 · Серия 4")
    }
}
