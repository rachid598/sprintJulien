import XCTest

final class SprintTimerUITests: XCTestCase {
    @MainActor
    func testManualRaceCanBeSavedAndReopened() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let create = app.buttons["race.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let name = app.textFields["race.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let raceName = "Course UI \(UUID().uuidString.prefix(8))"
        name.tap()
        name.typeText(raceName)

        let mode = app.buttons["race.mode"]
        if mode.exists { mode.tap() }
        else { app.descendants(matching: .any)["race.mode"].firstMatch.tap() }
        let stopwatch = app.buttons["Chronomètre"]
        if stopwatch.waitForExistence(timeout: 3) { stopwatch.tap() }
        else { app.staticTexts["Chronomètre"].firstMatch.tap() }
        app.buttons["race.prepare"].tap()
        let start = app.buttons["race.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
        start.tap()
        let mark = app.buttons["race.mark.manual"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        mark.tap()
        app.buttons["race.stop"].tap()
        let close = app.buttons["race.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let elapsed = app.staticTexts["race.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let finalElapsed = elapsed.label
        XCTAssertGreaterThan(Double(finalElapsed.replacingOccurrences(of: ",", with: ".")) ?? 0, 0)
        let results = app.descendants(matching: .any).matching(identifier: "race.results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Résultats · 1"].exists)
        attachScreenshot(app, name: "Course terminée avec arrivée manuelle")
        close.tap()

        let savedName = app.staticTexts[raceName].firstMatch
        XCTAssertTrue(savedName.waitForExistence(timeout: 5))
        savedName.tap()
        XCTAssertTrue(app.buttons["race.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[raceName].firstMatch.exists)
        XCTAssertEqual(app.staticTexts["race.elapsed"].label, finalElapsed)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "race.results").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Résultats · 1"].exists)
        attachScreenshot(app, name: "Course rouverte depuis l’historique")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
