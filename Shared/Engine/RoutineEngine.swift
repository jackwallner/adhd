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

    /// The short version keeps only steps not marked optional, when that leaves something to do.
    static func makeRun(for routine: Routine, shortVersion: Bool = false, at date: Date = .now) -> RoutineRun? {
        let useShort = shortVersion && routine.hasShortVersion
        let steps = useShort ? routine.shortSteps : routine.steps
        guard !steps.isEmpty else { return nil }
        return RoutineRun(
            routineID: routine.id,
            routineName: routine.name,
            steps: steps,
            startedAt: date,
            lastResumedAt: date,
            isShortVersion: useShort
        )
    }

    /// Advances one step and returns true when a step was advanced.
    @discardableResult
    static func completeCurrentStep(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard let step = activeStep(of: run) else { return false }
        let seconds = closeStep(&run, at: date)
        run.history.append(RunStepEntry(stepID: step.id, outcome: .done, fromIndex: run.currentStepIndex, seconds: seconds))
        run.completedStepCount = min(run.completedStepCount + 1, run.steps.count)
        run.currentStepIndex += 1
        return true
    }

    /// Skips one step without counting it as completed.
    @discardableResult
    static func skipCurrentStep(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard let step = activeStep(of: run) else { return false }
        let seconds = closeStep(&run, at: date)
        run.history.append(RunStepEntry(stepID: step.id, outcome: .skipped, fromIndex: run.currentStepIndex, seconds: seconds))
        run.currentStepIndex += 1
        return true
    }

    /// Moves the current step to the end of the run, so it comes back once the rest are done.
    @discardableResult
    static func doCurrentStepLater(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard let step = activeStep(of: run), run.canDoLater else { return false }
        let seconds = closeStep(&run, at: date)
        run.history.append(RunStepEntry(stepID: step.id, outcome: .later, fromIndex: run.currentStepIndex, seconds: seconds))
        run.steps.remove(at: run.currentStepIndex)
        run.steps.append(step)
        return true
    }

    /// Undoes the most recent done, skip, or later, and returns to that step.
    @discardableResult
    static func moveBack(_ run: inout RoutineRun, at date: Date = .now) -> Bool {
        guard !run.isPaused, let entry = run.history.popLast() else { return false }
        _ = closeStep(&run, at: date)
        switch entry.outcome {
        case .done:
            run.completedStepCount = max(0, run.completedStepCount - 1)
            run.currentStepIndex = entry.fromIndex
        case .skipped:
            run.currentStepIndex = entry.fromIndex
        case .later:
            guard let index = run.steps.lastIndex(where: { $0.id == entry.stepID }) else { return false }
            let step = run.steps.remove(at: index)
            let target = min(max(entry.fromIndex, 0), run.steps.count)
            run.steps.insert(step, at: target)
            run.currentStepIndex = target
        }
        run.stepElapsedSeconds = entry.seconds
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

    /// Active time on the current step, excluding paused time.
    static func stepElapsedSeconds(for run: RoutineRun, at date: Date = .now) -> TimeInterval {
        guard let resumedAt = run.lastResumedAt else { return run.stepElapsedSeconds }
        return run.stepElapsedSeconds + max(0, date.timeIntervalSince(resumedAt))
    }

    /// The moment the current step would have started if it had never been paused.
    static func stepStartedAt(for run: RoutineRun, at date: Date = .now) -> Date {
        date.addingTimeInterval(-stepElapsedSeconds(for: run, at: date))
    }

    static func remainingMinutes(for run: RoutineRun) -> Int {
        guard run.currentStepIndex < run.steps.count else { return 0 }
        return run.steps[run.currentStepIndex...].reduce(0) { $0 + $1.estimateMinutes }
    }

    static func completion(for run: RoutineRun, at date: Date = .now) -> RoutineCompletion {
        RoutineCompletion(
            routineID: run.routineID,
            routineName: run.routineName,
            completedAt: date,
            completedSteps: run.completedStepCount,
            totalSteps: run.steps.count,
            durationSeconds: elapsedSeconds(for: run, at: date),
            runID: run.id,
            isShortVersion: run.isShortVersion
        )
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

    private static func activeStep(of run: RoutineRun) -> RoutineStep? {
        guard !run.isPaused else { return nil }
        return run.currentStep
    }

    /// Books active time and returns the seconds spent on the step being left.
    private static func closeStep(_ run: inout RoutineRun, at date: Date) -> TimeInterval {
        accountActiveTime(&run, at: date)
        let seconds = run.stepElapsedSeconds
        run.stepElapsedSeconds = 0
        return seconds
    }

    private static func accountActiveTime(_ run: inout RoutineRun, at date: Date) {
        guard let resumedAt = run.lastResumedAt else { return }
        let active = max(0, date.timeIntervalSince(resumedAt))
        run.elapsedSeconds += active
        run.stepElapsedSeconds += active
        run.lastResumedAt = date
    }
}
