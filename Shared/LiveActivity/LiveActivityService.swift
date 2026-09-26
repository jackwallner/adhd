#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import os

/// Keeps one Live Activity alive while a routine runs, and none otherwise.
@MainActor
final class LiveActivityService: RunMirroring {
    static let shared = LiveActivityService()

    private let logger = Logger(subsystem: "NextCue", category: "LiveActivity")

    private init() {}

    /// `Activity` is not Sendable. It is only touched from the main actor here.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<RunActivityAttributes>
    }

    func sync(run: RoutineRun?, finishedRunID: UUID?, now: Date) {
        let existing = Activity<RunActivityAttributes>.activities
        guard let run, let step = run.currentStep, !NextCueDebugLaunch.suppressesLiveActivity else {
            for activity in existing {
                if activity.attributes.runID == finishedRunID {
                    finish(activity, at: now)
                } else {
                    end(activity)
                }
            }
            return
        }
        let state = RunActivityAttributes.ContentState(
            stepName: step.name,
            stepNote: step.details,
            nextStepName: run.nextStep?.name,
            stepNumber: run.currentStepIndex + 1,
            stepCount: run.steps.count,
            completedCount: run.completedStepCount,
            stepStartedAt: RoutineEngine.stepStartedAt(for: run, at: now),
            estimateMinutes: step.estimateMinutes,
            isPaused: run.isPaused
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = existing.first(where: { $0.attributes.runID == run.id }) {
            for activity in existing where activity.id != current.id { end(activity) }
            let box = ActivityBox(activity: current)
            Task { @MainActor in await box.activity.update(content) }
            return
        }
        for activity in existing { end(activity) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(
                attributes: RunActivityAttributes(runID: run.id, routineName: run.routineName),
                content: content
            )
        } catch {
            logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Shows "All done" briefly instead of vanishing mid-glance.
    private func finish(_ activity: Activity<RunActivityAttributes>, at now: Date) {
        var state = activity.content.state
        state.isFinished = true
        state.isPaused = false
        state.completedCount = state.stepCount
        let box = ActivityBox(activity: activity)
        let content = ActivityContent(state: state, staleDate: nil)
        Task { @MainActor in
            await box.activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(120)))
        }
    }

    private func end(_ activity: Activity<RunActivityAttributes>) {
        let box = ActivityBox(activity: activity)
        Task { @MainActor in await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#endif
