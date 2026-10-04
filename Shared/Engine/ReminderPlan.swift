import Foundation

struct PlannedReminder: Hashable, Sendable {
    var id: String
    var routineID: UUID
    var fireAt: Date
    var title: String
    var body: String
}

enum ReminderPlan {
    /// iOS allows 64 pending local notifications. Keep capacity for system and run alerts.
    static let scheduledLimit = 56
    static let horizonDays = 10
    static let routinePrefix = "nextcue.routine."
    static let nudgePrefix = "nextcue.nudge."
    static let snoozePrefix = "nextcue.snooze."
    static let snoozeMinutes = 10

    static func reminders(
        routines: [Routine],
        completions: [RoutineCompletion],
        activeRun: RoutineRun?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)

        for routine in routines where routine.isEnabled && routine.reminderEnabled {
            guard activeRun?.routineID != routine.id else { continue }
            let completedToday = RoutineEngine.hasCompletion(
                for: routine.id,
                on: now,
                completions: completions,
                calendar: calendar
            )

            for offset in 0...horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      !(offset == 0 && completedToday),
                      routine.schedule.weekdays.contains(calendar.component(.weekday, from: day)),
                      let fireAt = calendar.date(
                        bySettingHour: routine.schedule.hour,
                        minute: routine.schedule.minute,
                        second: 0,
                        of: day
                      ),
                      fireAt > now else { continue }

                planned.append(PlannedReminder(
                    id: "\(routinePrefix)\(routine.id.uuidString).\(Int(fireAt.timeIntervalSince1970))",
                    routineID: routine.id,
                    fireAt: fireAt,
                    title: "Time for \(displayName(routine.name))",
                    body: firstStepLine(for: routine)
                ))
            }
        }

        return Array(planned.sorted { $0.fireAt < $1.fireAt }.prefix(scheduledLimit))
    }

    /// One gentle check-in per step, a little after the step's estimate runs out.
    /// Paused runs get none: pausing is a choice, not drift.
    static func nudge(for run: RoutineRun?, now: Date = .now) -> PlannedReminder? {
        guard let run, !run.isPaused, let step = run.currentStep else { return nil }
        let estimate = TimeInterval(step.estimateMinutes * 60)
        let grace = min(max(120, estimate * 0.5), 600)
        let elapsed = RoutineEngine.stepElapsedSeconds(for: run, at: now)
        let fireAt = now.addingTimeInterval(max(estimate + grace - elapsed, 30))
        let stepName = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = run.nextStep.map { "Next up: \($0.name)." } ?? "It’s the last one."
        let body = step.startCue.map { "Stuck? Start with just this: \($0)." }
            ?? "No rush. Tap Done when it’s finished. \(after)"
        return PlannedReminder(
            id: "\(nudgePrefix)\(run.id.uuidString).\(run.currentStepIndex).\(run.history.count)",
            routineID: run.routineID,
            fireAt: fireAt,
            title: "Still on “\(stepName.isEmpty ? "this step" : stepName)”?",
            body: body
        )
    }

    static func snooze(for routine: Routine, now: Date = .now) -> PlannedReminder {
        PlannedReminder(
            id: "\(snoozePrefix)\(routine.id.uuidString)",
            routineID: routine.id,
            fireAt: now.addingTimeInterval(TimeInterval(snoozeMinutes * 60)),
            title: "Ready for \(displayName(routine.name))?",
            body: firstStepLine(for: routine)
        )
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "your routine" : trimmed
    }

    /// Naming the first small action makes starting easier than naming the whole routine.
    private static func firstStepLine(for routine: Routine) -> String {
        guard let step = routine.steps.first else { return "Your routine is ready when you are." }
        let first = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return "Your routine is ready when you are." }
        guard let cue = step.startCue else { return "Just the first step: \(first)." }
        return "Just the first step: \(first). Even smaller: \(cue)."
    }
}
