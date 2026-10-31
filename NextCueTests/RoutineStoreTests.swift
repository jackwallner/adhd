import XCTest
@testable import NextCue

@MainActor
final class RoutineStoreTests: XCTestCase {
    func testRestoredRunKeepsProgressAndStartsPausedAfterInterruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let startedAt = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [
            RoutineStep(name: "Get dressed"),
            RoutineStep(name: "Pack bag"),
        ])
        let firstLaunch = RoutineStore(fileURL: fileURL, now: startedAt)
        XCTAssertTrue(firstLaunch.saveRoutine(routine))
        XCTAssertTrue(firstLaunch.startRun(routineID: routine.id, now: startedAt))
        XCTAssertTrue(firstLaunch.completeCurrentStep(now: startedAt.addingTimeInterval(60)))

        let relaunchTime = startedAt.addingTimeInterval(3 * 3_600)
        let restored = RoutineStore(fileURL: fileURL, now: relaunchTime)

        XCTAssertEqual(restored.routines, [routine])
        XCTAssertEqual(restored.activeRun?.currentStepIndex, 1)
        XCTAssertEqual(restored.activeRun?.completedStepCount, 1)
        XCTAssertTrue(restored.activeRun?.isPaused == true)
        XCTAssertEqual(restored.activeRun.map { RoutineEngine.elapsedSeconds(for: $0, at: relaunchTime) }, 60)
    }

    func testEarlyFinishIsRecordedAsPartialAndDoesNotCountAsCompletedToday() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [
            RoutineStep(name: "Get dressed"),
            RoutineStep(name: "Pack bag"),
        ])
        let store = RoutineStore(fileURL: fileURL, now: now)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: now))
        XCTAssertTrue(store.completeCurrentStep(now: now.addingTimeInterval(30)))

        let partial = try XCTUnwrap(store.finishRun(now: now.addingTimeInterval(60)))

        XCTAssertFalse(partial.isComplete)
        XCTAssertFalse(store.completedToday(for: routine.id, now: now))
        XCTAssertEqual(store.completions(for: routine.id).count, 1)
    }

    func testShortRelaunchKeepsRunGoing() throws {
        let fileURL = try temporaryStateURL()
        let startedAt = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed"), RoutineStep(name: "Pack bag")])
        let first = RoutineStore(fileURL: fileURL, now: startedAt)
        XCTAssertTrue(first.saveRoutine(routine))
        XCTAssertTrue(first.startRun(routineID: routine.id, now: startedAt))

        let restored = RoutineStore(fileURL: fileURL, now: startedAt.addingTimeInterval(600))

        XCTAssertEqual(restored.activeRun?.isPaused, false)
    }

    func testRunFromEarlierDayIsClosedAsPartialOnLaunch() throws {
        let fileURL = try temporaryStateURL()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8)))
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed"), RoutineStep(name: "Pack bag")])
        let first = RoutineStore(fileURL: fileURL, now: startedAt, calendar: calendar)
        XCTAssertTrue(first.saveRoutine(routine))
        XCTAssertTrue(first.startRun(routineID: routine.id, now: startedAt))
        XCTAssertTrue(first.completeCurrentStep(now: startedAt.addingTimeInterval(120)))

        let nextDay = startedAt.addingTimeInterval(24 * 3_600)
        let restored = RoutineStore(fileURL: fileURL, now: nextDay, calendar: calendar)

        XCTAssertNil(restored.activeRun)
        let record = try XCTUnwrap(restored.completions.last)
        XCTAssertFalse(record.isComplete)
        XCTAssertEqual(record.completedSteps, 1)
        XCTAssertTrue(calendar.isDate(record.completedAt, inSameDayAs: startedAt))
    }

    func testRunFromEarlierDayIsClosedWhenTheAppReturnsToTheForeground() throws {
        let fileURL = try temporaryStateURL()
        let calendar = try utcCalendar()
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 21)))
        let routine = Routine(name: "Evening", steps: [RoutineStep(name: "Tidy"), RoutineStep(name: "Brush teeth")])
        let store = RoutineStore(fileURL: fileURL, now: startedAt, calendar: calendar)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: startedAt))
        XCTAssertTrue(store.completeCurrentStep(now: startedAt.addingTimeInterval(120)))
        XCTAssertTrue(store.pauseRun(now: startedAt.addingTimeInterval(180)))

        // iOS keeps the app in memory overnight, so nothing relaunches it. It only comes back to the foreground.
        store.refreshReminders(now: startedAt.addingTimeInterval(12 * 3_600), calendar: calendar)

        XCTAssertNil(store.activeRun)
        let record = try XCTUnwrap(store.completions.last)
        XCTAssertFalse(record.isComplete)
        XCTAssertEqual(record.completedSteps, 1)
        XCTAssertTrue(calendar.isDate(record.completedAt, inSameDayAs: startedAt))
    }

    func testForegroundKeepsARunStartedToday() throws {
        let fileURL = try temporaryStateURL()
        let calendar = try utcCalendar()
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8)))
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed"), RoutineStep(name: "Pack bag")])
        let store = RoutineStore(fileURL: fileURL, now: startedAt, calendar: calendar)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: startedAt))

        store.refreshReminders(now: startedAt.addingTimeInterval(30 * 60), calendar: calendar)

        XCTAssertEqual(store.activeRun?.routineID, routine.id)
        XCTAssertEqual(store.activeRun?.isPaused, false)
        XCTAssertTrue(store.completions.isEmpty)
    }

    func testForegroundJustAfterMidnightKeepsARunThatIsStillBeingDone() throws {
        let fileURL = try temporaryStateURL()
        let calendar = try utcCalendar()
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 23, minute: 50)))
        let routine = Routine(name: "Bedtime", steps: [RoutineStep(name: "Tidy"), RoutineStep(name: "Brush teeth")])
        let store = RoutineStore(fileURL: fileURL, now: startedAt, calendar: calendar)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: startedAt))
        XCTAssertTrue(store.completeCurrentStep(now: startedAt.addingTimeInterval(5 * 60)))

        // Ten minutes into the next day the user unlocks the phone mid-routine. The run is not left over, it is in use.
        store.refreshReminders(now: startedAt.addingTimeInterval(20 * 60), calendar: calendar)

        XCTAssertEqual(store.activeRun?.routineID, routine.id)
        XCTAssertEqual(store.activeRun?.isPaused, false)
        XCTAssertTrue(store.completions.isEmpty)
    }

    func testRoutinePausedOvernightStillGetsTomorrowsReminder() throws {
        let fileURL = try temporaryStateURL()
        let calendar = try utcCalendar()
        let spy = SpyReminders()
        let startedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8)))
        let routine = Routine(
            name: "Morning",
            steps: [RoutineStep(name: "Get dressed"), RoutineStep(name: "Pack bag")],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: Set(1...7))
        )
        let store = RoutineStore(fileURL: fileURL, reminderService: spy, now: startedAt, calendar: calendar)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: startedAt))
        XCTAssertTrue(store.pauseRun(now: startedAt.addingTimeInterval(300)))

        // The user never opens the app again that day. The next time it is foregrounded is the next morning.
        let nextMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7, minute: 30)))
        store.refreshReminders(now: nextMorning, calendar: calendar)

        let scheduled = ReminderPlan.reminders(
            routines: spy.lastRoutines,
            completions: spy.lastCompletions,
            activeRun: spy.lastActiveRun,
            now: nextMorning,
            calendar: calendar
        )
        let first = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(calendar.component(.day, from: first.fireAt), 22)
        XCTAssertEqual(calendar.component(.hour, from: first.fireAt), 8)
    }

    func testUndoFinishReopensRunOnLastStep() throws {
        let fileURL = try temporaryStateURL()
        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed"), RoutineStep(name: "Pack bag")])
        let store = RoutineStore(fileURL: fileURL, now: now)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: now))
        XCTAssertTrue(store.completeCurrentStep(now: now.addingTimeInterval(60)))
        XCTAssertTrue(store.completeCurrentStep(now: now.addingTimeInterval(120)))
        let record = try XCTUnwrap(store.completions.last)
        XCTAssertTrue(store.canUndoFinish(record))

        XCTAssertTrue(store.undoFinish(now: now.addingTimeInterval(130)))

        XCTAssertTrue(store.completions.isEmpty)
        XCTAssertEqual(store.activeRun?.currentStep?.name, "Pack bag")
        XCTAssertEqual(store.activeRun?.completedStepCount, 1)
    }

    func testCompletionIsLinkedToItsRun() throws {
        let fileURL = try temporaryStateURL()
        let routine = Routine(name: "Morning", steps: [RoutineStep(name: "Get dressed")])
        let store = RoutineStore(fileURL: fileURL)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id))
        let runID = try XCTUnwrap(store.activeRun?.id)
        XCTAssertTrue(store.completeCurrentStep())

        XCTAssertEqual(store.completion(forRun: runID)?.isComplete, true)
    }

    func testOlderSavedStateDecodesWithDefaults() throws {
        let json = """
        {"version":1,"routines":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Morning","steps":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Get dressed","estimateMinutes":5}],"schedule":{"hour":8,"minute":0,"weekdays":[2]},"isEnabled":true,"reminderEnabled":true}],
        "activeRun":{"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","routineID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","routineName":"Morning","steps":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Get dressed","estimateMinutes":5}],"currentStepIndex":0,"completedStepCount":0,"startedAt":0,"pausedAt":10,"elapsedSeconds":10},
        "completions":[]}
        """
        let fileURL = try temporaryStateURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)

        let store = RoutineStore(fileURL: fileURL, now: Date(timeIntervalSinceReferenceDate: 20))

        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(store.routines.first?.steps.first?.isOptional, false)
        XCTAssertEqual(store.activeRun?.history, [])
        XCTAssertEqual(store.activeRun?.isShortVersion, false)
        XCTAssertNil(store.routines.first?.steps.first?.smallestStart)
    }

    func testSmallestStartSavedMidRunUpdatesRunAndRoutine() throws {
        let fileURL = try temporaryStateURL()
        let now = try XCTUnwrap(Date(timeIntervalSince1970: 1_790_000_000))
        let shower = RoutineStep(name: "Shower")
        let routine = Routine(name: "Morning", steps: [shower, RoutineStep(name: "Get dressed")])
        let store = RoutineStore(fileURL: fileURL, now: now)
        XCTAssertTrue(store.saveRoutine(routine))
        XCTAssertTrue(store.startRun(routineID: routine.id, now: now))

        XCTAssertFalse(store.setSmallestStart("   ", forStep: shower.id))
        XCTAssertTrue(store.setSmallestStart("  Turn on the water ", forStep: shower.id))

        XCTAssertEqual(store.activeRun?.currentStep?.startCue, "Turn on the water")
        XCTAssertEqual(store.routines.first?.steps.first?.smallestStart, "Turn on the water")
        XCTAssertNil(store.routines.first?.steps.last?.smallestStart)
        let reloaded = RoutineStore(fileURL: fileURL, now: now)
        XCTAssertEqual(reloaded.routines.first?.steps.first?.startCue, "Turn on the water")
    }

    private func temporaryStateURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("state.json")
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}

/// Remembers what the store last asked the scheduler to plan from.
@MainActor
private final class SpyReminders: ReminderScheduling {
    private(set) var lastRoutines: [Routine] = []
    private(set) var lastCompletions: [RoutineCompletion] = []
    private(set) var lastActiveRun: RoutineRun?

    func configure() {}

    func reschedule(routines: [Routine], completions: [RoutineCompletion], activeRun: RoutineRun?, now: Date) {
        lastRoutines = routines
        lastCompletions = completions
        lastActiveRun = activeRun
    }
}
