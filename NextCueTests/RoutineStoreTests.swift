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
}
