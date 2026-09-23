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
        screen == "run" || screen == "paused" || screen == "complete"
    }

    static var startsOnRoutinesTab: Bool {
        screen == "routines" || screen == "editor"
    }

    static var needsPreparation: Bool {
        #if DEBUG
        hasArgument("-SeedScreenshotData") || screen != "home"
        #else
        false
        #endif
    }

    static var sampleRoutineName: String { "Morning start" }

    @MainActor
    static func prepare(routines: RoutineStore) {
        #if DEBUG
        guard needsPreparation else { return }
        if routines.routines.isEmpty {
            seed(routines: routines, includeSecondRoutine: screen != "complete")
        }
        guard let routine = routines.routines.first else { return }

        switch screen {
        case "run":
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id) }
            if routines.activeRun?.isPaused == true { _ = routines.resumeRun() }
        case "paused":
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id) }
            if routines.activeRun?.isPaused == false { _ = routines.pauseRun() }
        case "complete":
            if routines.activeRun == nil { _ = routines.startRun(routineID: routine.id) }
            while routines.activeRun != nil {
                guard routines.completeCurrentStep() else { break }
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
                RoutineStep(name: "Get out of bed", details: "Put both feet on the floor", estimateMinutes: 2),
                RoutineStep(name: "Get dressed", details: nil, estimateMinutes: 8),
                RoutineStep(name: "Eat something", details: "Keep it simple", estimateMinutes: 10),
                RoutineStep(name: "Gather what I need", details: nil, estimateMinutes: 4)
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
                RoutineStep(name: "Set out tomorrow’s clothes", estimateMinutes: 4),
                RoutineStep(name: "Charge my phone", estimateMinutes: 1),
                RoutineStep(name: "Put keys by the door", estimateMinutes: 2)
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
