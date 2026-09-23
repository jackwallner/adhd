import XCTest

/// Renders the real paywall under StoreKit Testing for App Store review screenshots.
@MainActor
final class PaywallSnapshotUITests: XCTestCase {
    func testPaywallSnapshots() {
        for plan in ["yearly", "monthly", "lifetime"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ResetUITestData", "-SeedScreenshotData", "-PaywallSnapshot", plan]
            app.launch()
            XCTAssertTrue(app.staticTexts["Make room for more routines"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$")).firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "paywall-\(plan)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
