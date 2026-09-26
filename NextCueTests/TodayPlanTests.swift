import XCTest
@testable import NextCue

final class TodayPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(hour: Int, minute: Int = 0) throws -> Date {
        // 2026-09-21 is a Monday.
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute)))
    }

    private func routine(_ name: String, hour: Int, reminder: Bool = true) -> Routine {
        Routine(
            name: name,
            steps: [RoutineStep(name: "Step")],
            schedule: RoutineSchedule(hour: hour, minute: 0, weekdays: reminder ? Set(1...7) : []),
            reminderEnabled: reminder
        )
    }

    func testRoutinesAreOrderedByTimeWithAnytimeLast() throws {
        let evening = routine("Evening", hour: 21)
        let anytime = routine("Anytime", hour: 8, reminder: false)
        let morning = routine("Morning", hour: 7)

        let plan = TodayPlan(routines: [evening, anytime, morning], completions: [], now: try date(hour: 6), calendar: calendar)

        XCTAssertEqual(plan.routines.map(\.name), ["Morning", "Evening", "Anytime"])
    }

    func testUpNextIsTheRoutineDueNowNotTheFirstCreated() throws {
        let evening = routine("Evening", hour: 21)
        let morning = routine("Morning", hour: 7)

        let plan = TodayPlan(routines: [evening, morning], completions: [], now: try date(hour: 7, minute: 20), calendar: calendar)

        XCTAssertEqual(plan.upNext?.name, "Morning")
    }

    func testLongMissedRoutineGivesWayToTheNextOne() throws {
        let morning = routine("Morning", hour: 7)
        let evening = routine("Evening", hour: 21)

        let plan = TodayPlan(routines: [morning, evening], completions: [], now: try date(hour: 15), calendar: calendar)

        XCTAssertEqual(plan.upNext?.name, "Evening")
    }

    func testCompletedRoutinesAreNotUpNext() throws {
        let morning = routine("Morning", hour: 7)
        let evening = routine("Evening", hour: 21)
        let done = RoutineCompletion(
            routineID: morning.id,
            routineName: morning.name,
            completedAt: try date(hour: 7, minute: 30),
            completedSteps: 1,
            totalSteps: 1,
            durationSeconds: 60
        )

        let plan = TodayPlan(routines: [morning, evening], completions: [done], now: try date(hour: 8), calendar: calendar)

        XCTAssertEqual(plan.upNext?.name, "Evening")
    }

    func testNothingUpNextWhenEverythingIsDone() throws {
        let morning = routine("Morning", hour: 7)
        let done = RoutineCompletion(
            routineID: morning.id,
            routineName: morning.name,
            completedAt: try date(hour: 7, minute: 30),
            completedSteps: 1,
            totalSteps: 1,
            durationSeconds: 60
        )

        let plan = TodayPlan(routines: [morning], completions: [done], now: try date(hour: 8), calendar: calendar)

        XCTAssertNil(plan.upNext)
        XCTAssertEqual(plan.routines.count, 1)
    }
}
