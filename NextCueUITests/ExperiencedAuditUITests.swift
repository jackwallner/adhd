import XCTest

/// Runtime probes for the experienced-user UX audit. Each test records what it saw as an
/// "observations" attachment and screenshots at the interesting moments, and only asserts on setup,
/// so a finding never hides the rest of the run.
@MainActor
final class ExperiencedAuditUITests: XCTestCase {
    private var observations: [String] = []

    override func setUp() {
        continueAfterFailure = true
        observations = []
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: observations.joined(separator: "\n"))
        attachment.name = "observations"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Probes

    /// A finished routine, then the way back into it for a second run the same day.
    func testRepeatRunAfterFinishingAndUndoTarget() {
        let app = launchSeeded(pro: false)
        shot("01-home-seeded-free")

        XCTAssertTrue(app.buttons["Start routine"].waitForExistence(timeout: 5))
        app.buttons["Start routine"].tap()
        XCTAssertTrue(app.staticTexts["STEP 1 OF 6"].waitForExistence(timeout: 5))
        app.buttons["run.done"].tap()
        let undo = app.buttons["Undo"]
        if undo.waitForExistence(timeout: 3) {
            let f = undo.frame
            note("Toast Undo hit frame: \(Int(f.width)) x \(Int(f.height)) pt at y=\(Int(f.minY)). Done button y=\(Int(app.buttons["run.done"].frame.minY)).")
            shot("02-toast-undo-after-done")
            sleep(5)
            note("Toast Undo still present 5 s after Done: \(undo.exists)")
        } else {
            note("Toast Undo never appeared after Done.")
        }

        for next in 3...6 {
            app.buttons["run.done"].tap()
            _ = app.staticTexts["STEP \(next) OF 6"].waitForExistence(timeout: 5)
        }
        app.buttons["run.done"].tap()
        XCTAssertTrue(app.staticTexts["That’s a wrap."].waitForExistence(timeout: 5))
        shot("03-finish-screen")
        app.buttons["Done"].tap()
        sleep(1)
        shot("04-home-after-finish")
        note("Row/lead play button for finished routine ('Start Morning start'): exists=\(app.buttons["Start Morning start"].exists)")
        note("Lead card 'Start routine' after finishing: exists=\(app.buttons["Start routine"].exists)")
        note("'That’s everything for today' notice: exists=\(app.staticTexts["That’s everything for today"].exists)")
        note("Any button labelled Run again: exists=\(app.buttons["Run again"].exists)")
    }

    /// With a run paused, the other routines cannot start and nothing says why.
    func testPausedRunBlocksOtherRoutines() {
        let app = launchSeeded(pro: true)
        startMorning(app)
        XCTAssertTrue(app.staticTexts["STEP 1 OF 6"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume routine"].waitForExistence(timeout: 5))
        shot("05-home-paused-run")
        let evening = app.buttons["Start Evening reset"]
        note("Start Evening reset while Morning is paused: exists=\(evening.exists) enabled=\(evening.exists ? evening.isEnabled : false)")
        let hints = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "finish", "end the")).count
        note("Static texts on Home explaining why other routines are dimmed: \(hints)")

        // Abandoning the paused run from Home: count the taps.
        app.buttons["Resume routine"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        shot("06-run-paused-screen")
        app.buttons["More routine options"].tap()
        shot("07-run-menu-paused")
        note("Run menu items while paused: Back a step=\(app.buttons["Back a step"].exists), Finish here=\(app.buttons["Finish here"].exists), End without saving=\(app.buttons["End without saving"].exists)")
        app.buttons["Finish here"].tap()
        sleep(1)
        shot("08-after-finish-here-no-confirm")
        note("'Finish here' on step 1 of 6 shows finish screen immediately: \(app.staticTexts["Nice going."].exists). Undo link present: \(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Not quite done")).firstMatch.exists)")
        app.buttons["Done"].tap()
        sleep(1)
        shot("09-home-after-partial-finish")
    }

    /// Delete a routine that has a paused run: what the confirmation says and what happens to the run.
    func testDeletingRoutineWithPausedRun() {
        let app = launchSeeded(pro: true)
        startMorning(app)
        XCTAssertTrue(app.staticTexts["STEP 1 OF 6"].waitForExistence(timeout: 5))
        app.buttons["run.done"].tap()
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume routine"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning start, ")).firstMatch
        let more = app.buttons["More options for Morning start"]
        guard row.exists || more.exists else {
            note("Paused routine has no row and no ellipsis menu on Home, so it cannot be edited or deleted without ending the run. Home buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))")
            return
        }
        if row.exists {
            row.tap()
        } else {
            more.tap()
            app.buttons["Edit routine"].tap()
        }
        XCTAssertTrue(app.buttons["setup.save"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Delete routine"], in: app)
        app.buttons["Delete routine"].tap()
        sleep(1)
        shot("10-delete-confirmation")
        let warnsAboutRun = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "run")).count
        note("Delete confirmation mentions the paused run: \(warnsAboutRun > 0)")
        app.buttons["Delete routine"].firstMatch.tap()
        sleep(1)
        shot("11-home-after-delete")
        note("Resume routine card after deleting its routine: exists=\(app.buttons["Resume routine"].exists)")
    }

    /// Lapsed or free user with a second routine: can it still be edited, deleted or started?
    func testLockedSecondRoutineIsStuck() {
        let app = launchSeeded(pro: false)
        let evening = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Evening reset")).firstMatch
        XCTAssertTrue(evening.waitForExistence(timeout: 5))
        shot("12-home-free-with-two-routines")
        evening.press(forDuration: 1.2)
        sleep(1)
        shot("13-long-press-locked-row")
        note("Context menu items on a locked row: Edit=\(app.buttons["Edit"].exists) Start=\(app.buttons["Start"].exists)")
        if app.buttons["Edit"].exists == false { app.tap() }
        evening.tap()
        XCTAssertTrue(app.staticTexts["Make room for more routines"].waitForExistence(timeout: 10))
        shot("14-tap-locked-row-opens-paywall")
        note("Tapping a locked routine opens the paywall, with no route to edit or delete it.")
    }

    /// Reordering steps and deleting one, the way the editor footer says to.
    func testEditorReorderAndSwipeDelete() {
        let app = launchSeeded(pro: false)
        openMorningEditor(app)
        let first = app.textFields["Step 1 name"]
        let second = app.textFields["Step 2 name"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        note("Before drag: step 1 = \(first.value as? String ?? "?"), step 2 = \(second.value as? String ?? "?")")
        shot("15-editor-top")

        let start = first.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -34, dy: 12))
        let end = second.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -34, dy: 60))
        start.press(forDuration: 1.0, thenDragTo: end)
        sleep(1)
        shot("16-editor-after-long-press-drag")
        note("After long-press drag: step 1 = \(app.textFields["Step 1 name"].value as? String ?? "?"), step 2 = \(app.textFields["Step 2 name"].value as? String ?? "?")")
        note("Reorder handle / Edit button present: handles=\(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder")).count) editButton=\(app.buttons["Edit"].exists)")

        app.textFields["Step 3 name"].swipeLeft()
        sleep(1)
        shot("17-editor-after-swipe-left")
        note("Swipe-left Delete button visible: \(app.buttons["Delete"].exists)")
    }

    /// Turning the reminder off and on again, for a routine on custom days.
    func testReminderToggleLosesCustomDays() {
        let app = launchSeeded(pro: false)
        openMorningEditor(app)
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] {
            let chip = app.buttons[day]
            scrollTo(chip, in: app)
            if chip.isSelected { chip.tap() }
        }
        for day in ["Saturday", "Sunday"] {
            let chip = app.buttons[day]
            scrollTo(chip, in: app)
            if !chip.isSelected { chip.tap() }
        }
        shot("18-editor-weekends-only")
        saveEditor(app)
        sleep(1)
        let weekendRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Weekends")).firstMatch
        note("Home row/label after saving weekend days: Weekends label exists=\(weekendRow.exists)")
        shot("19-home-weekends")

        // Reminder off, save, reopen.
        openMorningEditor(app)
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollTo(toggle, in: app)
        flip(toggle)
        note("Remind me value after turning off: \(toggle.value as? String ?? "?")")
        shot("20-editor-reminder-off")
        saveEditor(app)
        sleep(1)
        shot("21-home-reminder-off")
        note("Routine with reminder off shows 'Anytime' on Home: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Anytime")).count > 0)")

        openMorningEditor(app)
        let toggleAgain = app.switches.firstMatch
        XCTAssertTrue(toggleAgain.waitForExistence(timeout: 5))
        scrollTo(toggleAgain, in: app)
        note("Remind me value on reopen (expect 0): \(toggleAgain.value as? String ?? "?")")
        flip(toggleAgain)
        note("Remind me value after turning back on: \(toggleAgain.value as? String ?? "?")")
        sleep(1)
        let states = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].map { day -> String in
            let chip = app.buttons[day]
            scrollTo(chip, in: app)
            return "\(day.prefix(3))=\(chip.isSelected ? "on" : "off")"
        }
        note("Days after reminder off then on again (set to weekends before): \(states.joined(separator: " "))")
        shot("22-editor-reminder-back-on")
    }

    // MARK: Helpers

    private func launchSeeded(pro: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ResetUITestData", "-SeedScreenshotData"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        if pro { enablePro(app) }
        return app
    }

    private func enablePro(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        let toggle = app.switches["Pro access"]
        scrollTo(toggle, in: app)
        if toggle.exists && (toggle.value as? String) != "1" { flip(toggle) }
        note("Pro access switch value after flip: \(toggle.value as? String ?? "?")")
        app.buttons["Done"].firstMatch.tap()
        _ = app.buttons["Settings"].waitForExistence(timeout: 5)
    }

    private func startMorning(_ app: XCUIApplication) {
        let rowStart = app.buttons["Start Morning start"]
        if rowStart.waitForExistence(timeout: 3) { rowStart.tap() } else { app.buttons["Start routine"].tap() }
    }

    private func openMorningEditor(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Morning start, ")).firstMatch
        if row.waitForExistence(timeout: 2) {
            row.tap()
        } else {
            app.buttons["More options for Morning start"].tap()
            app.buttons["Edit routine"].tap()
        }
        XCTAssertTrue(app.buttons["setup.save"].waitForExistence(timeout: 5))
    }

    private func saveEditor(_ app: XCUIApplication) {
        app.buttons["setup.save"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        _ = app.buttons["setup.save"].waitForNonExistence(timeout: 5)
    }

    /// A Form row's centre is its label, so tap the switch at the trailing edge.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable { app.swipeUp() }
    }

    private func note(_ text: String) {
        observations.append(text)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
