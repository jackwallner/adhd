import Combine
import Foundation
import os

private struct RoutineStoreSnapshot: Codable, Sendable {
    var version: Int = 1
    var routines: [Routine] = []
    var activeRun: RoutineRun?
    var completions: [RoutineCompletion] = []
}

@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore(reminderService: ReminderService.shared)

    @Published private(set) var routines: [Routine] = []
    @Published private(set) var activeRun: RoutineRun?
    @Published private(set) var completions: [RoutineCompletion] = []
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let reminderService: ReminderScheduling?
    private let logger = Logger(subsystem: "NextCue", category: "RoutineStore")
    private let historyLimit = 1_000
    private var canWrite = true

    init(fileURL: URL? = nil, reminderService: ReminderScheduling? = nil, now: Date = .now) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.reminderService = reminderService
        load()
        reminderService?.configure()

        if var run = activeRun, !run.isPaused {
            RoutineEngine.recoverAfterInterruption(&run, at: now)
            if !commit({ $0.activeRun = run }) {
                activeRun = run
            }
        }
        propagateReminders(now: now)
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
    func startRun(routineID: UUID, now: Date = .now) -> Bool {
        guard activeRun == nil,
              let routine = routines.first(where: { $0.id == routineID }),
              let run = RoutineEngine.makeRun(for: routine, at: now) else { return false }
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

    func completedToday(for routineID: UUID, now: Date = .now, calendar: Calendar = .current) -> Bool {
        RoutineEngine.hasCompletion(for: routineID, on: now, completions: completions, calendar: calendar)
    }

    /// Rebuilds pending local reminders. Call after notification permission changes and on app foreground.
    func refreshReminders(now: Date = .now) {
        propagateReminders(now: now)
    }

    private func finish(_ run: RoutineRun, at date: Date) -> Bool {
        let completion = RoutineEngine.completion(for: run, at: date)
        return commit { snapshot in
            snapshot.activeRun = nil
            snapshot.completions.append(completion)
            snapshot.completions = Array(snapshot.completions.suffix(self.historyLimit))
        }
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
            propagateReminders()
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

    private func propagateReminders(now: Date = .now) {
        reminderService?.reschedule(
            routines: routines,
            completions: completions,
            activeRun: activeRun,
            now: now
        )
    }

    private static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("NextCue", isDirectory: true)
            .appendingPathComponent("nextcue-state.json")
    }
}
