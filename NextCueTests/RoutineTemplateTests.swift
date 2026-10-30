import XCTest
@testable import NextCue

final class RoutineTemplateTests: XCTestCase {
    private let filled = RoutineStarterTemplate.allCases.filter { $0 != .blank }

    func testEveryTemplateStepHasANameAndASmallestStart() {
        for template in filled {
            for step in template.setupSteps {
                XCTAssertFalse(step.name.isEmpty, "\(template)")
                XCTAssertFalse(step.smallestStart.isEmpty, "\(template): \(step.name)")
                XCTAssertGreaterThan(step.minutes, 0, "\(template): \(step.name)")
            }
        }
    }

    func testEveryTemplateHasAShortVersion() {
        for template in filled {
            let optional = template.setupSteps.filter(\.isOptional).count
            XCTAssertGreaterThan(optional, 0, "\(template)")
            XCTAssertLessThan(optional, template.setupSteps.count, "\(template)")
        }
    }

    func testTemplatesWithRemindersHaveDays() {
        for template in filled where template.hasReminder {
            XCTAssertFalse(template.weekdays.isEmpty, "\(template)")
        }
    }
}
