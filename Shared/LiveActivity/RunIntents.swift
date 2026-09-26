import AppIntents
import Foundation

/// The Done button on the Live Activity. A `LiveActivityIntent` runs in the app's
/// process, so the widget extension compiles an empty body and the app the real one.
struct CompleteStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish Step"
    static let description = IntentDescription("Marks the current step of your routine as done.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RoutineStore.shared.completeCurrentStep()
        #endif
        return .result()
    }
}

/// The Resume button on a paused Live Activity.
struct ResumeRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Routine"
    static let description = IntentDescription("Resumes your paused routine.")
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RoutineStore.shared.resumeRun()
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
/// "Start my routine" from Siri, Spotlight, or the Action button.
struct StartNextRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Routine"
    static let description = IntentDescription("Opens Next Cue on the first step of your next routine.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = RoutineStore.shared
        if store.activeRun == nil,
           let routine = TodayPlan(routines: store.routines, completions: store.completions).upNext,
           !NextCueRoutineAccess.requiresPro(routineID: routine.id, routines: store.routines, isPro: StoreService.shared.isPro) {
            store.startRun(routineID: routine.id)
        }
        if store.activeRun?.isPaused == true { store.resumeRun() }
        if store.activeRun != nil {
            NextCueRouter.shared.presentRun()
        } else {
            NextCueRouter.shared.showToday()
        }
        return .result()
    }
}

struct NextCueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNextRoutineIntent(),
            phrases: [
                "Start my routine in \(.applicationName)",
                "What's next in \(.applicationName)",
            ],
            shortTitle: "Start Next Routine",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: CompleteStepIntent(),
            phrases: ["Next step in \(.applicationName)", "Done in \(.applicationName)"],
            shortTitle: "Finish Step",
            systemImageName: "checkmark.circle"
        )
    }
}
#endif
