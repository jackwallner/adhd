import Foundation

/// Decides what Today shows: today's routines in time order, and the one to lead with.
struct TodayPlan: Sendable {
    /// How long after its time a scheduled routine still counts as the one to do now.
    static let dueWindowMinutes = 240
    /// How early a routine can lead before its time.
    static let leadMinutes = 30

    let routines: [Routine]
    let upNext: Routine?

    init(routines all: [Routine], completions: [RoutineCompletion], now: Date = .now, calendar: Calendar = .current) {
        let weekday = calendar.component(.weekday, from: now)
        let today = all.filter { routine in
            routine.isEnabled && (!routine.isScheduled || routine.schedule.weekdays.contains(weekday))
        }
        let ordered = today.enumerated().sorted { lhs, rhs in
            switch (lhs.element.isScheduled, rhs.element.isScheduled) {
            case (true, false): return true
            case (false, true): return false
            case (true, true) where lhs.element.schedule.minuteOfDay != rhs.element.schedule.minuteOfDay:
                return lhs.element.schedule.minuteOfDay < rhs.element.schedule.minuteOfDay
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        routines = ordered

        let open: [Routine] = ordered.filter { (routine: Routine) -> Bool in
            !RoutineEngine.hasCompletion(for: routine.id, on: now, completions: completions, calendar: calendar)
        }
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let scheduled: [Routine] = open.filter { $0.isScheduled }
        let due: Routine? = scheduled.last { (routine: Routine) -> Bool in
            let time = routine.schedule.minuteOfDay
            return time <= nowMinute + Self.leadMinutes && time >= nowMinute - Self.dueWindowMinutes
        }
        let upcoming: Routine? = scheduled.first { (routine: Routine) -> Bool in
            routine.schedule.minuteOfDay > nowMinute
        }
        let anytime: Routine? = open.first { (routine: Routine) -> Bool in !routine.isScheduled }
        if let due {
            upNext = due
        } else if let upcoming {
            upNext = upcoming
        } else {
            upNext = anytime ?? scheduled.last
        }
    }
}
