import Foundation

struct RoutineStep: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var details: String?
    var estimateMinutes: Int

    init(
        id: UUID = UUID(),
        name: String,
        details: String? = nil,
        estimateMinutes: Int = 5
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.estimateMinutes = max(1, estimateMinutes)
    }
}

/// A weekly schedule. Calendar weekdays use 1 for Sunday through 7 for Saturday.
struct RoutineSchedule: Codable, Hashable, Sendable {
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>

    init(hour: Int = 8, minute: Int = 0, weekdays: Set<Int> = [2, 3, 4, 5, 6]) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
    }
}

struct Routine: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var steps: [RoutineStep]
    var schedule: RoutineSchedule
    var isEnabled: Bool
    var reminderEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        steps: [RoutineStep],
        schedule: RoutineSchedule = RoutineSchedule(),
        isEnabled: Bool = true,
        reminderEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.reminderEnabled = reminderEnabled
    }
}

/// A persisted run snapshots its routine so edits do not change the steps in progress.
struct RoutineRun: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var routineID: UUID
    var routineName: String
    var steps: [RoutineStep]
    var currentStepIndex: Int
    var completedStepCount: Int
    var startedAt: Date
    var pausedAt: Date?
    var elapsedSeconds: TimeInterval
    var lastResumedAt: Date?

    init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        steps: [RoutineStep],
        currentStepIndex: Int = 0,
        completedStepCount: Int = 0,
        startedAt: Date = .now,
        pausedAt: Date? = nil,
        elapsedSeconds: TimeInterval = 0,
        lastResumedAt: Date? = nil
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.steps = steps
        self.currentStepIndex = min(max(currentStepIndex, 0), steps.count)
        self.completedStepCount = min(max(completedStepCount, 0), steps.count)
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.lastResumedAt = lastResumedAt ?? (pausedAt == nil ? startedAt : nil)
    }

    var currentStep: RoutineStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var isPaused: Bool { pausedAt != nil }
    var progress: Double { RoutineEngine.progress(of: self) }
}

struct RoutineCompletion: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var routineID: UUID
    var routineName: String
    var completedAt: Date
    var completedSteps: Int
    var totalSteps: Int
    var durationSeconds: TimeInterval

    var isComplete: Bool { totalSteps > 0 && completedSteps >= totalSteps }

    init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        completedAt: Date,
        completedSteps: Int,
        totalSteps: Int,
        durationSeconds: TimeInterval
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.completedAt = completedAt
        self.completedSteps = max(0, completedSteps)
        self.totalSteps = max(0, totalSteps)
        self.durationSeconds = max(0, durationSeconds)
    }
}
