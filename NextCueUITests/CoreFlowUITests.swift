import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
    func testFirstRoutineCanRunAndSecondRoutineOpensPro() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData"]
        app.launch()

        pickMorningTemplateScheduledToday(app)
        saveRoutine(app)

        XCTAssertTrue(app.buttons["Start routine"].waitForExistence(timeout: 5))
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.staticTexts["STEP 1 OF 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Get out of bed"].exists)
        app.buttons["run.done"].tap()
        XCTAssertTrue(app.staticTexts["STEP 2 OF 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Drink a glass of water"].exists)

        // Undo brings the step back, Later sends it to the end.
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["STEP 1 OF 6"].waitForExistence(timeout: 5))
        app.buttons["run.done"].tap()
        XCTAssertTrue(app.staticTexts["STEP 2 OF 6"].waitForExistence(timeout: 5))
        app.buttons["Do it later"].tap()
        XCTAssertTrue(app.staticTexts["Get dressed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["STEP 2 OF 6"].exists)

        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume routine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Get dressed"].exists)

        app.buttons["Add routine"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Make room for more routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
    }

    func testShortVersionRunsOnlyRequiredSteps() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData"]
        app.launch()

        pickMorningTemplateScheduledToday(app)
        saveRoutine(app)

        let short = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Low energy?")).firstMatch
        XCTAssertTrue(short.waitForExistence(timeout: 5))
        short.tap()
        XCTAssertTrue(app.staticTexts["STEP 1 OF 4"].waitForExistence(timeout: 5))
        for next in 2...4 {
            app.buttons["run.done"].tap()
            XCTAssertTrue(app.staticTexts["STEP \(next) OF 4"].waitForExistence(timeout: 5))
        }
        app.buttons["run.done"].tap()
        XCTAssertTrue(app.staticTexts["That’s a wrap."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "You did the short version")).firstMatch.exists)
    }

    /// The template runs on weekdays. Add today so the test does not depend on the day it runs.
    private func pickMorningTemplateScheduledToday(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Choose a starter routine"].waitForExistence(timeout: 10))
        app.buttons["Choose a starter routine"].tap()
        let template = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning start,")).firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        let today = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: .now) - 1]
        let chip = app.buttons[today]
        for _ in 0..<4 where !chip.isHittable { app.swipeUp() }
        if !chip.isSelected { chip.tap() }
    }

    /// Taps must wait for the editor sheet to finish dismissing, or they land on the sheet.
    private func saveRoutine(_ app: XCUIApplication) {
        app.buttons["Save routine"].tap()
        dismissNotificationPrompt(app)
        XCTAssertTrue(app.buttons["Save routine"].waitForNonExistence(timeout: 5))
    }

    private func dismissNotificationPrompt(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
