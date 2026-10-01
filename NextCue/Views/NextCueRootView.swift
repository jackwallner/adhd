import SwiftUI
import UIKit

struct NextCueRootView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter
    @State private var launchPrepared = !NextCueDebugLaunch.needsPreparation
    @State private var showPaywallSnapshot = false

    var body: some View {
        Group {
            if launchPrepared {
                HomeView()
            } else {
                ProgressView()
                    .tint(NextCueStyle.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NextCueStyle.background.ignoresSafeArea())
            }
        }
        .tint(NextCueStyle.accent)
        .task {
            purchases.start()
            if !launchPrepared {
                NextCueDebugLaunch.prepare(routines: routines)
                routines.refreshReminders()
                launchPrepared = true
                if NextCueDebugLaunch.opensRoutineRun { router.showRun = true }
            }
            if NextCueDebugLaunch.isPaywallSnapshot { showPaywallSnapshot = true }
        }
        .sheet(isPresented: $showPaywallSnapshot) { NextCuePaywallView() }
        .fullScreenCover(isPresented: $router.showRun) { RoutineRunView() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            routines.refreshReminders()
            purchases.start()
        }
    }
}

/// Starting a routine from anywhere: respects the free limit and never starts a second run.
@MainActor
enum RoutineLauncher {
    enum Outcome {
        case presented
        case needsPro
        case failed
    }

    static func start(
        _ routine: Routine,
        shortVersion: Bool = false,
        routines: RoutineStore,
        isPro: Bool,
        router: NextCueRouter
    ) -> Outcome {
        guard !NextCueRoutineAccess.requiresPro(routineID: routine.id, routines: routines.routines, isPro: isPro) else {
            return .needsPro
        }
        if routines.activeRun == nil {
            guard routines.startRun(routineID: routine.id, shortVersion: shortVersion) else { return .failed }
        }
        router.showRun = true
        return .presented
    }
}

enum NextCueRoutineAccess {
    static func requiresPro(routineID: UUID, routines: [Routine], isPro: Bool) -> Bool {
        !isPro && routines.first?.id != routineID
    }
}

enum NextCueSchedule {
    static func label(for schedule: RoutineSchedule, remindersEnabled: Bool = true) -> String {
        guard remindersEnabled, !schedule.weekdays.isEmpty else { return "Anytime" }
        return "\(days(schedule.weekdays)) · \(NextCueFormat.time(hour: schedule.hour, minute: schedule.minute))"
    }

    static func days(_ weekdays: Set<Int>) -> String {
        switch weekdays {
        case Set(1...7): return "Daily"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            let firstWeekday = Calendar.current.firstWeekday
            return weekdays
                .sorted { ($0 - firstWeekday + 7) % 7 < ($1 - firstWeekday + 7) % 7 }
                .map { symbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }
}
