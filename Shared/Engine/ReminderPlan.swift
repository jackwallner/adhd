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

                let name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = name.isEmpty ? "your routine" : name
                planned.append(PlannedReminder(
                    id: "nextcue.routine.\(routine.id.uuidString).\(Int(fireAt.timeIntervalSince1970))",
                    routineID: routine.id,
                    fireAt: fireAt,
                    title: "A cue for \(displayName)",
                    body: "Your routine is ready when you are."
                ))
            }
        }

        return Array(planned.sorted { $0.fireAt < $1.fireAt }.prefix(scheduledLimit))
    }
}
