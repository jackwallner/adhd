import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
    func testFirstRoutineCanRunAndSecondRoutineOpensPro() {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData"]
        app.launch()

        app.buttons["Choose a starter routine"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning start,")).firstMatch.tap()
        app.buttons["Save routine"].tap()
        app.alerts["Routine saved"].buttons["Done"].tap()

        XCTAssertTrue(app.buttons["Start routine"].waitForExistence(timeout: 5))
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.staticTexts["Get out of bed"].waitForExistence(timeout: 5))
        app.buttons["Done with this step"].tap()
        XCTAssertTrue(app.staticTexts["Get dressed"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume routine"].waitForExistence(timeout: 5))

        app.buttons["Add a routine"].tap()
        XCTAssertTrue(app.staticTexts["Make room for more routines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
    }
}
