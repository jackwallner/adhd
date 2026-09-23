import Foundation

enum RoutineEngine {
    static func nextScheduledDate(
        for routine: Routine,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard routine.isEnabled, !routine.schedule.weekdays.isEmpty else { return nil }
        let startOfToday = calendar.startOfDay(for: date)

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  routine.schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                  let scheduled = calendar.date(
                    bySettingHour: routine.schedule.hour,
                    minute: routine.schedule.minute,
                    second: 0,
                    of: day
                  ),
                  scheduled > date else { continue }
            return scheduled
        }
        return nil
    }

    static func makeRun(for routine: Routine, at date: Date = .now) -> RoutineRun? {
        guard !routine.steps.isEmpty else { return nil }
        return RoutineRun(
            routineID: routine.id,
            routineName: routine.name,
            steps: routine.steps,
            startedAt: date,
            lastResumedAt: date
        )
    }

    /// Advances one step and returns true when a step was advanced.
    @discardableResult
    static func completeCurrentStep(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard !run.isPaused, run.currentStepIndex < run.steps.count else { return false }
        accountActiveTime(&run, at: date)
        run.completedStepCount = min(run.completedStepCount + 1, run.steps.count)
        run.currentStepIndex += 1
        return true
    }

    /// Skips one step without counting it as completed.
    @discardableResult
    static func skipCurrentStep(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard !run.isPaused, run.currentStepIndex < run.steps.count else { return false }
        accountActiveTime(&run, at: date)
        run.currentStepIndex += 1
        return true
    }

    static func pause(_ run: inout RoutineRun, at date: Date = .now) {
        guard !run.isPaused else { return }
        accountActiveTime(&run, at: date)
        run.pausedAt = date
        run.lastResumedAt = nil
    }

    /// A relaunch cannot know how long the app was interrupted. Keep persisted time and resume paused.
    static func recoverAfterInterruption(_ run: inout RoutineRun, at date: Date = .now) {
        guard !run.isPaused else { return }
        run.pausedAt = date
        run.lastResumedAt = nil
    }

    static func resume(_ run: inout RoutineRun, at date: Date = .now) {
        guard run.isPaused else { return }
        run.pausedAt = nil
        run.lastResumedAt = date
    }

    static func progress(of run: RoutineRun) -> Double {
        guard !run.steps.isEmpty else { return 0 }
        return min(max(Double(run.completedStepCount) / Double(run.steps.count), 0), 1)
    }

    static func elapsedSeconds(for run: RoutineRun, at date: Date = .now) -> TimeInterval {
        guard let resumedAt = run.lastResumedAt else { return run.elapsedSeconds }
        return run.elapsedSeconds + max(0, date.timeIntervalSince(resumedAt))
    }

    static func completion(for run: RoutineRun, at date: Date = .now) -> RoutineCompletion {
        RoutineCompletion(
            routineID: run.routineID,
            routineName: run.routineName,
            completedAt: date,
            completedSteps: run.completedStepCount,
            totalSteps: run.steps.count,
            durationSeconds: elapsedSeconds(for: run, at: date)
        )
    }

    private static func accountActiveTime(_ run: inout RoutineRun, at date: Date) {
        guard let resumedAt = run.lastResumedAt else { return }
        run.elapsedSeconds += max(0, date.timeIntervalSince(resumedAt))
        run.lastResumedAt = date
    }

    static func hasCompletion(
        for routineID: UUID,
        on date: Date,
        completions: [RoutineCompletion],
        calendar: Calendar = .current
    ) -> Bool {
        completions.contains { completion in
            completion.isComplete &&
                completion.routineID == routineID &&
                calendar.isDate(completion.completedAt, inSameDayAs: date)
        }
    }
}
