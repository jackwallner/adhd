import Foundation

struct RoutineStep: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var details: String?
    var estimateMinutes: Int
    /// Optional steps are left out of the short version of a routine.
    var isOptional: Bool

    init(
        id: UUID = UUID(),
        name: String,
        details: String? = nil,
        estimateMinutes: Int = 5,
        isOptional: Bool = false
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.estimateMinutes = max(1, estimateMinutes)
        self.isOptional = isOptional
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        estimateMinutes = max(1, try container.decode(Int.self, forKey: .estimateMinutes))
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
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

    var minuteOfDay: Int { hour * 60 + minute }
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

    var isScheduled: Bool { reminderEnabled && !schedule.weekdays.isEmpty }
    var shortSteps: [RoutineStep] { steps.filter { !$0.isOptional } }
    /// A short version exists only when it would drop something and keep something.
    var hasShortVersion: Bool { !shortSteps.isEmpty && shortSteps.count < steps.count }
    var estimatedMinutes: Int { steps.reduce(0) { $0 + $1.estimateMinutes } }
    var shortEstimatedMinutes: Int { shortSteps.reduce(0) { $0 + $1.estimateMinutes } }
}

/// What happened to a step the run moved past. Kept in order so a step can be undone.
struct RunStepEntry: Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case done
        case skipped
        /// Moved to the end of the run from `fromIndex`.
        case later
    }

    var stepID: UUID
    var outcome: Outcome
    var fromIndex: Int
    var seconds: TimeInterval
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
    /// Active time spent on the current step before `lastResumedAt`.
    var stepElapsedSeconds: TimeInterval
    var history: [RunStepEntry]
    var isShortVersion: Bool

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
        lastResumedAt: Date? = nil,
        stepElapsedSeconds: TimeInterval = 0,
        history: [RunStepEntry] = [],
        isShortVersion: Bool = false
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
        self.stepElapsedSeconds = max(0, stepElapsedSeconds)
        self.history = history
        self.isShortVersion = isShortVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        routineID = try container.decode(UUID.self, forKey: .routineID)
        routineName = try container.decode(String.self, forKey: .routineName)
        steps = try container.decode([RoutineStep].self, forKey: .steps)
        currentStepIndex = try container.decode(Int.self, forKey: .currentStepIndex)
        completedStepCount = try container.decode(Int.self, forKey: .completedStepCount)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
        lastResumedAt = try container.decodeIfPresent(Date.self, forKey: .lastResumedAt)
        stepElapsedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .stepElapsedSeconds) ?? 0
        history = try container.decodeIfPresent([RunStepEntry].self, forKey: .history) ?? []
        isShortVersion = try container.decodeIfPresent(Bool.self, forKey: .isShortVersion) ?? false
    }

    var currentStep: RoutineStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var nextStep: RoutineStep? {
        guard steps.indices.contains(currentStepIndex + 1) else { return nil }
        return steps[currentStepIndex + 1]
    }

    var isPaused: Bool { pausedAt != nil }
    var progress: Double { RoutineEngine.progress(of: self) }
    var stepsLeftAfterCurrent: Int { max(0, steps.count - currentStepIndex - 1) }
    var canMoveBack: Bool { !history.isEmpty }
    var canDoLater: Bool { stepsLeftAfterCurrent > 0 }
}

struct RoutineCompletion: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var routineID: UUID
    var routineName: String
    var completedAt: Date
    var completedSteps: Int
    var totalSteps: Int
    var durationSeconds: TimeInterval
    var runID: UUID?
    var isShortVersion: Bool

    var isComplete: Bool { totalSteps > 0 && completedSteps >= totalSteps }

    init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        completedAt: Date,
        completedSteps: Int,
        totalSteps: Int,
        durationSeconds: TimeInterval,
        runID: UUID? = nil,
        isShortVersion: Bool = false
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.completedAt = completedAt
        self.completedSteps = max(0, completedSteps)
        self.totalSteps = max(0, totalSteps)
        self.durationSeconds = max(0, durationSeconds)
        self.runID = runID
        self.isShortVersion = isShortVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        routineID = try container.decode(UUID.self, forKey: .routineID)
        routineName = try container.decode(String.self, forKey: .routineName)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        completedSteps = try container.decode(Int.self, forKey: .completedSteps)
        totalSteps = try container.decode(Int.self, forKey: .totalSteps)
        durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        runID = try container.decodeIfPresent(UUID.self, forKey: .runID)
        isShortVersion = try container.decodeIfPresent(Bool.self, forKey: .isShortVersion) ?? false
    }
}
