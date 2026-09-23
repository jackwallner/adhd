import XCTest
@testable import NextCue

final class ReminderPlanTests: XCTestCase {
    func testPlanSkipsCompletedOccurrenceButKeepsFutureSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7)))
        let routine = Routine(
            name: "Morning reset",
            steps: [RoutineStep(name: "Open curtains")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: [2, 3])
        )
        let completed = RoutineCompletion(
            routineID: routine.id,
            routineName: routine.name,
            completedAt: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 6))),
            completedSteps: 1,
            totalSteps: 1,
            durationSeconds: 60
        )

        let reminders = ReminderPlan.reminders(
            routines: [routine],
            completions: [completed],
            activeRun: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(reminders.count, 3)
        XCTAssertEqual(calendar.component(.weekday, from: reminders[0].fireAt), 3)
        XCTAssertEqual(reminders[0].routineID, routine.id)
    }

    func testPlanSkipsPausedAndDisabledReminderRoutines() throws {
        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(
            name: "Pause",
            steps: [RoutineStep(name: "Start")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )
        var paused = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: now))
        RoutineEngine.pause(&paused, at: now)

        let pausedPlan = ReminderPlan.reminders(
            routines: [routine],
            completions: [],
            activeRun: paused,
            now: now.addingTimeInterval(1)
        )
        var noReminder = routine
        noReminder.reminderEnabled = false
        let disabledPlan = ReminderPlan.reminders(
            routines: [noReminder],
            completions: [],
            activeRun: nil,
            now: now
        )

        XCTAssertTrue(pausedPlan.isEmpty)
        XCTAssertTrue(disabledPlan.isEmpty)
    }
}
