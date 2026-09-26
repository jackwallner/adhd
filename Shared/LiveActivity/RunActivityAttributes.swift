#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The Live Activity for a routine run. The name stays fixed; the step arrives as state.
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var stepName: String
        var stepNote: String?
        var nextStepName: String?
        var stepNumber: Int
        var stepCount: Int
        var completedCount: Int
        /// When the current step would have started with pauses removed, so a timer can count up from it.
        var stepStartedAt: Date
        var estimateMinutes: Int
        var isPaused: Bool
        /// Set on the final update, so the Lock Screen can say the routine is done before it goes away.
        var isFinished = false

        var estimateEndsAt: Date { stepStartedAt.addingTimeInterval(TimeInterval(estimateMinutes * 60)) }
    }

    var runID: UUID
    var routineName: String
}
#endif
