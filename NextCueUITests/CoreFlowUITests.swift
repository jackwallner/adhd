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
        XCTAssertTrue(app.staticTexts["Make room for more routines"].waitForExistence(timeout: 10))
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

    func testStuckShrinksTheStepAndStartingBringsItBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData"]
        app.launch()

        pickMorningTemplateScheduledToday(app)
        saveRoutine(app)
        XCTAssertTrue(app.buttons["Start routine"].waitForExistence(timeout: 5))
        app.buttons["Start routine"].tap()

        // A template step shrinks to its smallest start, and starting brings the whole step back.
        XCTAssertTrue(app.buttons["run.stuck"].waitForExistence(timeout: 5))
        app.buttons["run.stuck"].tap()
        XCTAssertTrue(app.staticTexts["Sit up and put both feet on the floor"].waitForExistence(timeout: 5))
        app.buttons["run.started"].tap()
        XCTAssertTrue(app.staticTexts["Nice start. Keep going."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Get out of bed"].exists)
        app.buttons["run.done"].tap()
        XCTAssertTrue(app.staticTexts["STEP 2 OF 6"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Nice start. Keep going."].exists)

        // The next step shrinks too, and the whole step can come back without starting.
        app.buttons["run.stuck"].tap()
        XCTAssertTrue(app.staticTexts["Fill the glass"].waitForExistence(timeout: 5))
        app.buttons["Show the whole step"].tap()
        XCTAssertTrue(app.staticTexts["Drink a glass of water"].waitForExistence(timeout: 5))
    }

    func testSmallerStartCanBeSavedFromTheRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData"]
        app.launch()

        let template = app.buttons["template.blank"]
        XCTAssertTrue(template.waitForExistence(timeout: 10))
        template.tap()
        let name = app.textFields["Routine name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Laundry")
        let step = app.textFields["Step 1 name"]
        step.tap()
        step.typeText("Fold the clothes")
        saveRoutine(app)

        XCTAssertTrue(app.buttons["Start routine"].waitForExistence(timeout: 5))
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.buttons["run.stuck"].waitForExistence(timeout: 5))
        app.buttons["run.stuck"].tap()
        XCTAssertTrue(app.staticTexts["Do ten seconds of it"].waitForExistence(timeout: 5))
        app.buttons["Save a smaller start"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Pick up one shirt")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Pick up one shirt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save a smaller start"].exists)
    }

    /// The template runs on weekdays. Add today so the test does not depend on the day it runs.
    private func pickMorningTemplateScheduledToday(_ app: XCUIApplication) {
        let template = app.buttons["template.morning"]
        XCTAssertTrue(template.waitForExistence(timeout: 10))
        template.tap()
        XCTAssertTrue(app.buttons["setup.save"].waitForExistence(timeout: 5))
        let today = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: .now) - 1]
        let chip = app.buttons[today]
        for _ in 0..<4 where !chip.isHittable { app.swipeUp() }
        if !chip.isSelected { chip.tap() }
    }

    /// Taps must wait for the editor sheet to finish dismissing, or they land on the sheet.
    private func saveRoutine(_ app: XCUIApplication) {
        app.buttons["setup.save"].tap()
        dismissNotificationPrompt(app)
        XCTAssertTrue(app.buttons["setup.save"].waitForNonExistence(timeout: 5))
    }

    private func dismissNotificationPrompt(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
