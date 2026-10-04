import Combine
import Foundation
import os

private struct RoutineStoreSnapshot: Codable, Sendable {
    var version: Int = 1
    var routines: [Routine] = []
    var activeRun: RoutineRun?
    var completions: [RoutineCompletion] = []
}

/// Mirrors the active run somewhere outside the app, such as a Live Activity.
@MainActor
protocol RunMirroring: AnyObject {
    /// `finishedRunID` names a run that just ended by finishing its last step, as opposed to being cancelled.
    func sync(run: RoutineRun?, finishedRunID: UUID?, now: Date)
}

@MainActor
final class RoutineStore: ObservableObject {
    /// A running step left alone longer than this on relaunch is treated as interrupted.
    static let interruptionThreshold: TimeInterval = 2 * 60 * 60

    static let shared = RoutineStore(reminderService: ReminderService.shared, runMirror: LiveActivityService.shared)

    @Published private(set) var routines: [Routine] = []
    @Published private(set) var activeRun: RoutineRun?
    @Published private(set) var completions: [RoutineCompletion] = []
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let reminderService: ReminderScheduling?
    private let runMirror: RunMirroring?
    private let logger = Logger(subsystem: "NextCue", category: "RoutineStore")
    private let historyLimit = 1_000
    /// The run the last step just finished, kept in memory so an accidental final tap can be undone.
    private var justFinished: (run: RoutineRun, completionID: UUID)?
    private var canWrite = true

    init(
        fileURL: URL? = nil,
        reminderService: ReminderScheduling? = nil,
        runMirror: RunMirroring? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.reminderService = reminderService
        self.runMirror = runMirror
        load()
        reminderService?.configure()
        recoverActiveRun(now: now, calendar: calendar)
        propagate(now: now)
    }

    func saveRoutine(_ routine: Routine) -> Bool {
        commit { snapshot in
            if let index = snapshot.routines.firstIndex(where: { $0.id == routine.id }) {
                snapshot.routines[index] = routine
            } else {
                snapshot.routines.append(routine)
            }
        }
    }

    func deleteRoutine(id: UUID) -> Bool {
        commit { snapshot in
            snapshot.routines.removeAll { $0.id == id }
            if snapshot.activeRun?.routineID == id { snapshot.activeRun = nil }
        }
    }

    @discardableResult
    func startRun(routineID: UUID, shortVersion: Bool = false, now: Date = .now) -> Bool {
        justFinished = nil
        guard activeRun == nil,
              let routine = routines.first(where: { $0.id == routineID }),
              let run = RoutineEngine.makeRun(for: routine, shortVersion: shortVersion, at: now) else { return false }
        return commit { $0.activeRun = run }
    }

    /// Returns true when the step advance was saved. The active run clears at the last step.
    @discardableResult
    func completeCurrentStep(now: Date = .now) -> Bool {
        guard var run = activeRun,
              RoutineEngine.completeCurrentStep(&run, at: now) else { return false }
        if run.currentStepIndex == run.steps.count {
            return finish(run, at: now)
        }
        return commit { $0.activeRun = run }
    }

    @discardableResult
    func skipCurrentStep(now: Date = .now) -> Bool {
        guard var run = activeRun, RoutineEngine.skipCurrentStep(&run, at: now) else { return false }
        if run.currentStepIndex == run.steps.count {
            return finish(run, at: now)
        }
        return commit { $0.activeRun = run }
    }

    @discardableResult
    func doCurrentStepLater(now: Date = .now) -> Bool {
        guard var run = activeRun, RoutineEngine.doCurrentStepLater(&run, at: now) else { return false }
        return commit { $0.activeRun = run }
    }

    /// Undoes the last done, skip, or later.
    @discardableResult
    func moveBack(now: Date = .now) -> Bool {
        guard var run = activeRun, RoutineEngine.moveBack(&run, at: now) else { return false }
        return commit { $0.activeRun = run }
    }

    /// Saves a smallest start to the step in the run and in its routine, so it is there next time too.
    @discardableResult
    func setSmallestStart(_ text: String, forStep stepID: UUID) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return commit { snapshot in
            if var run = snapshot.activeRun {
                for index in run.steps.indices where run.steps[index].id == stepID {
                    run.steps[index].smallestStart = trimmed
                }
                snapshot.activeRun = run
            }
            for routineIndex in snapshot.routines.indices {
                for index in snapshot.routines[routineIndex].steps.indices
                where snapshot.routines[routineIndex].steps[index].id == stepID {
                    snapshot.routines[routineIndex].steps[index].smallestStart = trimmed
                }
            }
        }
    }

    @discardableResult
    func pauseRun(now: Date = .now) -> Bool {
        guard var run = activeRun, !run.isPaused else { return false }
        RoutineEngine.pause(&run, at: now)
        return commit { $0.activeRun = run }
    }

    @discardableResult
    func resumeRun(now: Date = .now) -> Bool {
        guard var run = activeRun, run.isPaused else { return false }
        RoutineEngine.resume(&run, at: now)
        return commit { $0.activeRun = run }
    }

    /// Ends early and records the completed portion of the routine.
    @discardableResult
    func finishRun(now: Date = .now) -> RoutineCompletion? {
        guard let run = activeRun else { return nil }
        let completion = RoutineEngine.completion(for: run, at: now)
        let saved = commit { snapshot in
            snapshot.activeRun = nil
            snapshot.completions.append(completion)
            snapshot.completions = Array(snapshot.completions.suffix(self.historyLimit))
        }
        return saved ? completion : nil
    }

    @discardableResult
    func cancelRun() -> Bool {
        guard activeRun != nil else { return false }
        justFinished = nil
        return commit { $0.activeRun = nil }
    }

    func nextScheduledDate(for routine: Routine, after date: Date = .now, calendar: Calendar = .current) -> Date? {
        RoutineEngine.nextScheduledDate(for: routine, after: date, calendar: calendar)
    }

    func completions(for routineID: UUID) -> [RoutineCompletion] {
        completions
            .filter { $0.routineID == routineID }
            .sorted { $0.completedAt > $1.completedAt }
    }

    func completion(forRun runID: UUID) -> RoutineCompletion? {
        completions.last { $0.runID == runID }
    }

    func completedToday(for routineID: UUID, now: Date = .now, calendar: Calendar = .current) -> Bool {
        RoutineEngine.hasCompletion(for: routineID, on: now, completions: completions, calendar: calendar)
    }

    /// Rebuilds pending local reminders and the Live Activity. Call after permission or preference changes and on app foreground.
    func refreshReminders(now: Date = .now) {
        propagate(now: now)
    }

    private func finish(_ run: RoutineRun, at date: Date) -> Bool {
        let completion = RoutineEngine.completion(for: run, at: date)
        justFinished = (run, completion.id)
        let saved = commit { snapshot in
            snapshot.activeRun = nil
            snapshot.completions.append(completion)
            snapshot.completions = Array(snapshot.completions.suffix(self.historyLimit))
        }
        if !saved { justFinished = nil }
        return saved
    }

    func canUndoFinish(_ completion: RoutineCompletion) -> Bool {
        activeRun == nil && justFinished?.completionID == completion.id
    }

    /// Reopens the run that the last step finished, back on that step.
    @discardableResult
    func undoFinish(now: Date = .now) -> Bool {
        guard activeRun == nil, let finished = justFinished else { return false }
        var run = finished.run
        run.lastResumedAt = now
        run.pausedAt = nil
        guard RoutineEngine.moveBack(&run, at: now) else { return false }
        let saved = commit { snapshot in
            snapshot.activeRun = run
            snapshot.completions.removeAll { $0.id == finished.completionID }
        }
        if saved { justFinished = nil }
        return saved
    }

    @discardableResult
    private func commit(_ change: (inout RoutineStoreSnapshot) -> Void) -> Bool {
        guard canWrite else { return false }
        var snapshot = currentSnapshot()
        change(&snapshot)

        do {
            try persist(snapshot)
            apply(snapshot)
            persistenceError = nil
            propagate()
            return true
        } catch {
            persistenceError = "Your change could not be saved. Please try again."
            logger.error("Could not persist routine state: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(RoutineStoreSnapshot.self, from: data)
            apply(snapshot)
        } catch {
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("nextcue-state-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
                persistenceError = "Saved routines could not be read. A recovery copy was kept."
            } catch {
                canWrite = false
                persistenceError = "Saved routines could not be read. Changes cannot be saved yet."
                logger.error("Could not recover routine state: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func currentSnapshot() -> RoutineStoreSnapshot {
        RoutineStoreSnapshot(routines: routines, activeRun: activeRun, completions: completions)
    }

    private func apply(_ snapshot: RoutineStoreSnapshot) {
        routines = snapshot.routines
        activeRun = snapshot.activeRun
        completions = snapshot.completions
    }

    private func persist(_ snapshot: RoutineStoreSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func propagate(now: Date = .now) {
        reminderService?.reschedule(
            routines: routines,
            completions: completions,
            activeRun: activeRun,
            now: now
        )
        runMirror?.sync(run: activeRun, finishedRunID: justFinished?.run.id, now: now)
    }

    /// A run from an earlier day is closed as a partial record so it cannot block today's reminders.
    /// A run left running for hours resumes paused, since the app cannot know how long it was set aside.
    private func recoverActiveRun(now: Date, calendar: Calendar) {
        guard var run = activeRun else { return }
        if !calendar.isDate(run.startedAt, inSameDayAs: now) {
            RoutineEngine.recoverAfterInterruption(&run, at: now)
            let closedAt = run.startedAt.addingTimeInterval(run.elapsedSeconds)
            let completion = RoutineEngine.completion(for: run, at: closedAt)
            if !commit({ snapshot in
                snapshot.activeRun = nil
                snapshot.completions.append(completion)
                snapshot.completions = Array(snapshot.completions.suffix(self.historyLimit))
            }) {
                activeRun = nil
            }
            return
        }
        guard !run.isPaused, let resumedAt = run.lastResumedAt,
              now.timeIntervalSince(resumedAt) > Self.interruptionThreshold else { return }
        RoutineEngine.recoverAfterInterruption(&run, at: now)
        if !commit({ $0.activeRun = run }) {
            activeRun = run
        }
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("NextCue", isDirectory: true)
            .appendingPathComponent("nextcue-state.json")
    }
}
