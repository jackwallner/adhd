import XCTest
@testable import NextCue

final class RoutineEngineTests: XCTestCase {
    func testNextScheduledDateMovesToNextEnabledDayAfterTodayHasPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9)))
        let routine = Routine(
            name: "Morning",
            steps: [RoutineStep(name: "Get dressed")],
            schedule: RoutineSchedule(hour: 8, minute: 30, weekdays: [2, 4])
        )

        let next = try XCTUnwrap(RoutineEngine.nextScheduledDate(for: routine, after: monday, calendar: calendar))

        XCTAssertEqual(calendar.component(.weekday, from: next), 4)
        XCTAssertEqual(calendar.component(.hour, from: next), 8)
        XCTAssertEqual(calendar.component(.minute, from: next), 30)
    }

    func testNextScheduledDateUsesNextWeekWhenOnlyEnabledDayHasPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8, minute: 30)))
        let routine = Routine(
            name: "Weekly reset",
            steps: [RoutineStep(name: "Clear the desk")],
            schedule: RoutineSchedule(hour: 8, minute: 30, weekdays: [2])
        )

        let next = try XCTUnwrap(RoutineEngine.nextScheduledDate(for: routine, after: monday, calendar: calendar))

        XCTAssertEqual(calendar.component(.day, from: next), 28)
    }

    func testPauseAndResumePreserveElapsedRunTime() throws {
        let startedAt = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed")])
        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: startedAt))

        RoutineEngine.pause(&run, at: startedAt.addingTimeInterval(90))
        XCTAssertTrue(run.isPaused)
        XCTAssertEqual(RoutineEngine.elapsedSeconds(for: run, at: startedAt.addingTimeInterval(600)), 90)

        RoutineEngine.resume(&run, at: startedAt.addingTimeInterval(600))
        XCTAssertFalse(run.isPaused)
        XCTAssertEqual(RoutineEngine.elapsedSeconds(for: run, at: startedAt.addingTimeInterval(630)), 120)
    }

    func testProgressCountsCompletedStepsButNotSkippedSteps() throws {
        let routine = Routine(name: "Morning", steps: [
            RoutineStep(name: "Get dressed"),
            RoutineStep(name: "Pack bag"),
            RoutineStep(name: "Shoes on"),
        ])
        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine))

        XCTAssertEqual(RoutineEngine.progress(of: run), 0)
        XCTAssertTrue(RoutineEngine.completeCurrentStep(&run))
        XCTAssertEqual(RoutineEngine.progress(of: run), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(RoutineEngine.skipCurrentStep(&run))
        XCTAssertEqual(RoutineEngine.progress(of: run), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertTrue(RoutineEngine.completeCurrentStep(&run))
        XCTAssertEqual(RoutineEngine.progress(of: run), 2.0 / 3.0, accuracy: 0.001)
    }

    func testPartialRunDoesNotCountAsDailyCompletion() throws {
        let completedAt = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routineID = UUID()
        let partial = RoutineCompletion(
            routineID: routineID,
            routineName: "Morning",
            completedAt: completedAt,
            completedSteps: 1,
            totalSteps: 2,
            durationSeconds: 60
        )
        let full = RoutineCompletion(
            routineID: routineID,
            routineName: "Morning",
            completedAt: completedAt,
            completedSteps: 2,
            totalSteps: 2,
            durationSeconds: 120
        )

        XCTAssertFalse(RoutineEngine.hasCompletion(for: routineID, on: completedAt, completions: [partial]))
        XCTAssertTrue(RoutineEngine.hasCompletion(for: routineID, on: completedAt, completions: [full]))
    }
}
