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

        let relaunchTime = startedAt.addingTimeInterval(3_600)
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
}
