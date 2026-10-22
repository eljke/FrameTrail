import XCTest

final class FrameTrailSmokeTests: XCTestCase {
    @MainActor
    func testSaveFinishedMovieAndReflection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["addManualTitle"].waitForExistence(timeout: 5))
        capture("01-overview", app: app)

        tabs.buttons["Библиотека"].tap()
        let addTitle = app.buttons["libraryAddTitle"]
        XCTAssertTrue(addTitle.waitForExistence(timeout: 5))
        addTitle.tap()

        let name = app.textFields["manualTitleName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Arrival")
        app.buttons["confirmManualTitle"].tap()

        let movie = app.staticTexts["Arrival"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        capture("02-library", app: app)
        movie.tap()

        let finished = app.switches["finishedToggle"]
        XCTAssertTrue(finished.waitForExistence(timeout: 5))
        reveal(finished, app: app)
        finished.tap()

        let writeReflection = app.buttons["writeReflection"]
        XCTAssertTrue(writeReflection.waitForExistence(timeout: 5))
        reveal(writeReflection, app: app)
        capture("03-finished-movie", app: app)
        writeReflection.tap()

        let summary = app.textViews["reflectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()
        let thought = "The ending reframes the earlier choices. I want to revisit the opening scene."
        summary.typeText(thought)
        let save = app.buttons["saveReflection"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts[thought].firstMatch.waitForExistence(timeout: 5))

        tabs.buttons["Дневник"].tap()
        XCTAssertTrue(app.staticTexts["Arrival"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[thought].firstMatch.waitForExistence(timeout: 5))
        capture("04-journal", app: app)

        tabs.buttons["Настройки"].tap()
        XCTAssertTrue(tabs.buttons["Настройки"].isSelected)
        capture("05-settings", app: app)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected control must be visible before interaction")
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
