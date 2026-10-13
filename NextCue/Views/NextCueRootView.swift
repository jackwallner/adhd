import StoreKit
import SwiftUI
import UIKit

struct NextCueRootView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter
    @State private var launchPrepared = !NextCueDebugLaunch.needsPreparation
    @State private var showPaywallSnapshot = false
    @State private var reviewTask: Task<Void, Never>?
    @Environment(\.requestReview) private var requestReview

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
        .fullScreenCover(isPresented: $router.showRun, onDismiss: scheduleReviewRequestAfterPositiveMoment) {
            RoutineRunView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            routines.refreshReminders()
            purchases.start()
        }
    }

    /// The rating ask after a finished routine: Apple's own prompt, no question
    /// in front of it. Waits for Home to settle, then asks only if nothing is
    /// presented. A blocked ask keeps the moment pending for the next finish.
    private func scheduleReviewRequestAfterPositiveMoment() {
        guard ReviewPromptTracker.hasPendingPositiveMoment else { return }
        reviewTask?.cancel()
        reviewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isHomeClear,
                  ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedSetup: !routines.routines.isEmpty)
            else { return }
            ReviewPromptTracker.markShown()
            requestReview()
        }
    }

    /// No run, sheet, paywall or alert is up over Home.
    private var isHomeClear: Bool {
        guard !router.showRun, !showPaywallSnapshot, UIApplication.shared.applicationState == .active else { return false }
        return !UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
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
