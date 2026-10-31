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

    func testPlanSkipsTheDayOfAPausedRunAndDisabledReminderRoutines() throws {
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

        XCTAssertFalse(pausedPlan.contains { Calendar.current.isDate($0.fireAt, inSameDayAs: now) })
        XCTAssertTrue(disabledPlan.isEmpty)
    }

    func testRunInProgressSilencesOnlyTheDayItStartedOn() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7, minute: 30)))
        let routine = Routine(
            name: "Morning",
            steps: [RoutineStep(name: "Get dressed")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )
        let run = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: now))

        let reminders = ReminderPlan.reminders(
            routines: [routine],
            completions: [],
            activeRun: run,
            now: now,
            calendar: calendar
        )

        // Today's 8:00 is skipped because the routine is already running. Tomorrow and the days after keep theirs.
        XCTAssertEqual(reminders.count, ReminderPlan.horizonDays)
        let first = try XCTUnwrap(reminders.first)
        XCTAssertEqual(calendar.component(.day, from: first.fireAt), 22)
    }

    func testRunLeftOpenFromAnEarlierDayDoesNotSilenceToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 21)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 7, minute: 30)))
        let routine = Routine(
            name: "Evening",
            steps: [RoutineStep(name: "Tidy one surface")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )
        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: startedAt))
        RoutineEngine.pause(&run, at: startedAt.addingTimeInterval(300))

        let reminders = ReminderPlan.reminders(
            routines: [routine],
            completions: [],
            activeRun: run,
            now: now,
            calendar: calendar
        )

        let first = try XCTUnwrap(reminders.first)
        XCTAssertEqual(calendar.component(.day, from: first.fireAt), 21)
        XCTAssertEqual(calendar.component(.hour, from: first.fireAt), 8)
    }

    func testReminderNamesTheFirstStep() throws {
        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(
            name: "Morning",
            steps: [RoutineStep(name: "Get out of bed")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )

        let reminder = try XCTUnwrap(ReminderPlan.reminders(routines: [routine], completions: [], activeRun: nil, now: now).first)

        XCTAssertEqual(reminder.body, "Just the first step: Get out of bed.")
    }

    func testReminderAndNudgeOfferTheSmallestStart() throws {
        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(
            name: "Morning",
            steps: [
                RoutineStep(name: "Get out of bed", smallestStart: "Put both feet on the floor"),
                RoutineStep(name: "Eat", smallestStart: " "),
            ],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )

        let reminder = try XCTUnwrap(ReminderPlan.reminders(routines: [routine], completions: [], activeRun: nil, now: now).first)
        XCTAssertEqual(reminder.body, "Just the first step: Get out of bed. Even smaller: Put both feet on the floor.")

        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: now))
        XCTAssertEqual(ReminderPlan.nudge(for: run, now: now)?.body, "Stuck? Start with just this: Put both feet on the floor.")
        XCTAssertTrue(RoutineEngine.completeCurrentStep(&run, at: now))
        XCTAssertTrue(ReminderPlan.nudge(for: run, now: now)?.body.hasPrefix("No rush.") == true)
    }

    func testNudgeFiresAfterEstimatePlusGraceAndNotWhilePaused() throws {
        let start = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [
            RoutineStep(name: "Get dressed", estimateMinutes: 8),
            RoutineStep(name: "Eat", estimateMinutes: 10),
        ])
        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine, at: start))

        let nudge = try XCTUnwrap(ReminderPlan.nudge(for: run, now: start.addingTimeInterval(60)))
        XCTAssertEqual(nudge.fireAt, start.addingTimeInterval(480 + 240))
        XCTAssertTrue(nudge.title.contains("Get dressed"))
        XCTAssertTrue(nudge.body.contains("Next up: Eat."))

        RoutineEngine.pause(&run, at: start.addingTimeInterval(90))
        XCTAssertNil(ReminderPlan.nudge(for: run, now: start.addingTimeInterval(100)))
    }

    func testNudgeIdentifierChangesWithEachStep() throws {
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "A"), RoutineStep(name: "B")])
        var run = try XCTUnwrap(RoutineEngine.makeRun(for: routine))
        let first = try XCTUnwrap(ReminderPlan.nudge(for: run))
        XCTAssertTrue(RoutineEngine.completeCurrentStep(&run))
        let second = try XCTUnwrap(ReminderPlan.nudge(for: run))

        XCTAssertNotEqual(first.id, second.id)
    }
}
