import Foundation

enum NextCueDebugLaunch {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var screen: String {
        #if DEBUG
        value(after: "-Screen") ?? (hasArgument("-PaywallSnapshot") ? "paywall" : "home")
        #else
        "home"
        #endif
    }

    static var isPaywallSnapshot: Bool {
        #if DEBUG
        hasArgument("-PaywallSnapshot") || screen == "paywall"
        #else
        false
        #endif
    }

    static var paywallPlan: NextCuePlan {
        #if DEBUG
        switch value(after: "-PaywallSnapshot")?.lowercased() ?? "yearly" {
        case "monthly": .monthly
        case "lifetime": .lifetime
        default: .yearly
        }
        #else
        .yearly
        #endif
    }

    static var opensRoutineRun: Bool {
        screen == "run" || screen == "stuck" || screen == "paused" || screen == "complete"
    }

    static var needsPreparation: Bool {
        #if DEBUG
        hasArgument("-SeedScreenshotData") || screen != "home"
        #else
        false
        #endif
    }

    static var sampleRoutineName: String { "Morning start" }

    /// Captures and UI tests must not leave a Live Activity behind for the next run.
    static var suppressesLiveActivity: Bool {
        #if DEBUG
        needsPreparation || hasArgument("-ResetUITestData")
        #else
        false
        #endif
    }

    @MainActor
    static func prepare(routines: RoutineStore) {
        #if DEBUG
        guard needsPreparation else { return }
        if routines.routines.isEmpty {
            seed(routines: routines, includeSecondRoutine: screen != "complete")
        }
        guard let routine = routines.routines.first else { return }

        switch screen {
        case "run", "stuck":
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id) }
            if routines.activeRun?.isPaused == true { _ = routines.resumeRun() }
        case "paused":
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id) }
            if routines.activeRun?.isPaused == false { _ = routines.pauseRun() }
        case "complete":
            // Each step takes its estimate, so the finish screen shows a believable active time.
            var stepEnd = Date.now.addingTimeInterval(-TimeInterval(routine.estimatedMinutes * 60))
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id, now: stepEnd) }
            while let step = routines.activeRun?.currentStep {
                stepEnd = min(stepEnd.addingTimeInterval(TimeInterval(step.estimateMinutes * 60)), .now)
                guard routines.completeCurrentStep(now: stepEnd) else { break }
            }
        default:
            break
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private static func seed(routines: RoutineStore, includeSecondRoutine: Bool) {
        let morning = Routine(
            name: sampleRoutineName,
            steps: [
                RoutineStep(name: "Get out of bed", estimateMinutes: 2, smallestStart: "Sit up and put both feet on the floor"),
                RoutineStep(name: "Drink a glass of water", estimateMinutes: 1, smallestStart: "Fill the glass"),
                RoutineStep(name: "Get dressed", estimateMinutes: 8, smallestStart: "Put on one sock"),
                RoutineStep(name: "Make the bed", details: "Good enough is fine", estimateMinutes: 3, isOptional: true, smallestStart: "Pull the cover up"),
                RoutineStep(name: "Eat something", details: "Keep it simple", estimateMinutes: 10, smallestStart: "Open the fridge"),
                RoutineStep(name: "Gather what I need", estimateMinutes: 4, isOptional: true, smallestStart: "Pick up your keys")
            ],
            schedule: RoutineSchedule(hour: 8, minute: 0, weekdays: [2, 3, 4, 5, 6]),
            isEnabled: true,
            reminderEnabled: true
        )
        _ = routines.saveRoutine(morning)

        guard includeSecondRoutine else { return }
        let evening = Routine(
            name: "Evening reset",
            steps: [
                RoutineStep(name: "Set out tomorrow’s clothes", estimateMinutes: 4, smallestStart: "Pick a shirt"),
                RoutineStep(name: "Tidy one surface", estimateMinutes: 5, isOptional: true, smallestStart: "Put away three things"),
                RoutineStep(name: "Charge my phone", estimateMinutes: 1, smallestStart: "Find the charger"),
                RoutineStep(name: "Set out what I need", estimateMinutes: 2, smallestStart: "Put your bag by the door")
            ],
            schedule: RoutineSchedule(hour: 21, minute: 0, weekdays: Set(1...7)),
            isEnabled: true,
            reminderEnabled: true
        )
        _ = routines.saveRoutine(evening)
    }

    private static func hasArgument(_ argument: String) -> Bool {
        arguments.contains(argument)
    }

    private static func value(after argument: String) -> String? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") ? nil : value
    }
    #else
    private static func hasArgument(_ argument: String) -> Bool { false }
    private static func value(after argument: String) -> String? { nil }
    #endif
}
