import XCTest

final class FrameTrailSmokeTests: XCTestCase {
    @MainActor
    func testSwitchApplicationLanguage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--language=en"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        capture("10-settings-english", app: app)
        app.buttons["appLanguage"].tap()
        app.buttons["Русский"].tap()
        XCTAssertTrue(app.tabBars.buttons["Библиотека"].waitForExistence(timeout: 5))
        capture("11-settings-russian", app: app)
    }

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

        let writeReflection = app.buttons["rateTitle"]
        XCTAssertTrue(writeReflection.waitForExistence(timeout: 5))
        reveal(writeReflection, app: app)
        capture("03-finished-movie", app: app)
        writeReflection.tap()

        let summary = app.textViews["reflectionSummary"]
        let rating = app.descendants(matching: .any).matching(identifier: "starRating").firstMatch
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["ratingValue"].label, "8")
        reveal(summary, app: app)
        XCTAssertTrue(summary.exists)
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
        XCTAssertTrue(app.staticTexts["8/10"].firstMatch.exists)

        tabs.buttons["Настройки"].tap()
        XCTAssertTrue(tabs.buttons["Настройки"].isSelected)
        capture("05-settings", app: app)
        let guide = app.buttons["openQuickGuide"]
        reveal(guide, app: app)
        guide.tap()
        XCTAssertTrue(app.navigationBars["Краткий гид"].waitForExistence(timeout: 5))
        app.buttons["closeGuide"].tap()
        let storage = app.buttons["storageSettings"]
        reveal(storage, app: app)
        storage.tap()
        let clean = app.buttons["clearImageCache"]
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        reveal(clean, app: app)
        clean.tap()
        XCTAssertTrue(app.staticTexts["cacheCleanupResult"].waitForExistence(timeout: 5))
        capture("09-storage", app: app)
    }

    @MainActor
    func testSaveImpressionsWithoutSummaryOrRating() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let add = app.buttons["addManualTitle"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let name = app.textFields["manualTitleName"]
        name.tap()
        name.typeText("A personal memory")
        app.buttons["confirmManualTitle"].tap()
        app.tabBars.buttons["Библиотека"].tap()
        let title = app.staticTexts["A personal memory"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let finished = app.switches["finishedToggle"]
        reveal(finished, app: app)
        finished.tap()
        let rate = app.buttons["rateTitle"]
        reveal(rate, app: app)
        rate.tap()
        let stars = app.descendants(matching: .any).matching(identifier: "starRating").firstMatch
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        stars.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        app.buttons["saveReflection"].tap()
        reveal(rate, app: app)
        rate.tap()
        app.buttons["Без оценки"].tap()
        XCTAssertTrue(app.buttons["saveReflection"].isEnabled, "An existing rating-only review must allow clearing its score")
        app.buttons["saveReflection"].tap()
        let write = app.buttons["rateTitle"]
        reveal(write, app: app)
        write.tap()
        app.buttons["toggleReviewDetails"].tap()
        let liked = app.textViews["reflectionLiked"]
        reveal(liked, app: app)
        XCTAssertTrue(liked.exists)
        liked.tap()
        liked.typeText("The music stayed with me")
        XCTAssertTrue(app.buttons["saveReflection"].isEnabled)
        app.buttons["saveReflection"].tap()
        app.tabBars.buttons["Дневник"].tap()
        XCTAssertTrue(app.staticTexts["+ The music stayed with me"].waitForExistence(timeout: 5))
        capture("06-impressions-only", app: app)
    }

    @MainActor
    func testRateWatchedEpisodeAndKeepItsImpressions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let add = app.buttons["addManualTitle"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        app.textFields["manualTitleName"].tap()
        app.textFields["manualTitleName"].typeText("My series")
        app.buttons["manualTitleKind"].tap()
        app.buttons["Сериал"].tap()
        app.buttons["confirmManualTitle"].tap()
        app.tabBars.buttons["Библиотека"].tap()
        let title = app.staticTexts["My series"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let disclosure = app.buttons["sourcesDisclosure"]
        reveal(disclosure, app: app)
        disclosure.tap()
        let source = app.buttons["importSource"]
        reveal(source, app: app)
        source.tap()
        let text = app.textViews["sourceText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("A character chooses to return home.")
        app.buttons["saveSource"].tap()
        let watched = app.buttons["Просмотрено: сезон 1, серия 1"]
        XCTAssertTrue(watched.waitForExistence(timeout: 5))
        reveal(watched, app: app)
        watched.tap()
        app.buttons["Действия с серией"].firstMatch.tap()
        app.buttons["Оценить серию и впечатления"].tap()
        let rating = app.descendants(matching: .any).matching(identifier: "starRating").firstMatch
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["ratingValue"].label, "4")
        rating.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: rating.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["ratingValue"].label, "9")
        capture("08-episode-rating", app: app)
        app.buttons["toggleReviewDetails"].tap()
        let disliked = app.textViews["reflectionDisliked"]
        reveal(disliked, app: app)
        disliked.tap()
        disliked.typeText("The final scene felt rushed")
        app.buttons["saveReflection"].tap()
        app.tabBars.buttons["Дневник"].tap()
        XCTAssertTrue(app.staticTexts["Сезон 1 · Серия 1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["− The final scene felt rushed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["9/10"].firstMatch.exists)
        capture("07-episode-review", app: app)
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
