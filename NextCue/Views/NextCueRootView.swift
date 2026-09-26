import SwiftUI
import UIKit

struct NextCueRootView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter
    @State private var selectedTab: NextCueTab = NextCueDebugLaunch.startsOnRoutinesTab ? .routines : .today
    @State private var launchPrepared = !NextCueDebugLaunch.needsPreparation
    @State private var showPaywallSnapshot = false

    var body: some View {
        Group {
            if launchPrepared {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(NextCueTab.today)

                    RoutineLibraryView()
                        .tabItem { Label("Routines", systemImage: "list.bullet.rectangle") }
                        .tag(NextCueTab.routines)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(NextCueTab.settings)
                }
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
        .onChange(of: router.todayRequest) { _, _ in selectedTab = .today }
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

struct RoutineLibraryView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter

    @State private var showNewRoutine = NextCueDebugLaunch.screen == "editor"
    @State private var showPaywall = false
    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if routines.routines.isEmpty {
                        emptyState
                    } else {
                        ForEach(routines.routines) { routine in
                            let isLocked = NextCueRoutineAccess.requiresPro(
                                routineID: routine.id,
                                routines: routines.routines,
                                isPro: purchases.isPro
                            )
                            RoutineLibraryCard(
                                routine: routine,
                                isLocked: isLocked,
                                isRunning: routines.activeRun?.routineID == routine.id,
                                edit: { isLocked ? (showPaywall = true) : (editingRoutine = routine) },
                                start: { start(routine) }
                            )
                            .contextMenu {
                                if !isLocked {
                                    Button { start(routine) } label: { Label("Start", systemImage: "play") }
                                    if routine.hasShortVersion {
                                        Button { start(routine, shortVersion: true) } label: {
                                            Label("Start short version", systemImage: "leaf")
                                        }
                                    }
                                    Button { editingRoutine = routine } label: { Label("Edit", systemImage: "pencil") }
                                }
                            }
                        }

                        if !purchases.isPro {
                            Text("One routine is free. Pro adds unlimited routines.")
                                .font(.footnote)
                                .foregroundStyle(NextCueStyle.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 6)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(NextCueStyle.background.ignoresSafeArea())
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addRoutine) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("Add routine")
                }
            }
            .sheet(isPresented: $showNewRoutine) { RoutineSetupView() }
            .sheet(isPresented: $showPaywall) { NextCuePaywallView() }
            .sheet(item: $editingRoutine) { RoutineSetupView(routine: $0) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            NextCueIcon(symbol: "sparkles")
            Text("Build a routine that fits your day")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(NextCueStyle.ink)
            Text("Start from a simple template, then change any step or reminder.")
                .font(.body)
                .foregroundStyle(NextCueStyle.secondary)
            Button("Choose a starter routine", action: addRoutine)
                .buttonStyle(NextCuePrimaryButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 24)
    }

    private func start(_ routine: Routine, shortVersion: Bool = false) {
        let outcome = RoutineLauncher.start(
            routine,
            shortVersion: shortVersion,
            routines: routines,
            isPro: purchases.isPro,
            router: router
        )
        if outcome == .needsPro { showPaywall = true }
    }

    private func addRoutine() {
        guard routines.routines.first?.id == nil || purchases.isPro else {
            showPaywall = true
            return
        }
        showNewRoutine = true
    }
}

private enum NextCueTab: Hashable {
    case today
    case routines
    case settings
}

enum NextCueRoutineAccess {
    static func requiresPro(routineID: UUID, routines: [Routine], isPro: Bool) -> Bool {
        !isPro && routines.first?.id != routineID
    }
}

private struct RoutineLibraryCard: View {
    let routine: Routine
    let isLocked: Bool
    let isRunning: Bool
    let edit: () -> Void
    let start: () -> Void

    var body: some View {
        NextCueCard(padding: 16) {
            HStack(spacing: 14) {
                Button(action: edit) {
                    HStack(spacing: 14) {
                        NextCueIcon(symbol: isLocked ? "lock.fill" : "checklist")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NextCueStyle.ink)
                                .multilineTextAlignment(.leading)
                            Text("\(NextCueFormat.steps(routine.steps.count)) · about \(NextCueFormat.minutes(routine.estimatedMinutes))")
                                .font(.subheadline)
                                .foregroundStyle(NextCueStyle.secondary)
                            Text(NextCueSchedule.label(for: routine.schedule, remindersEnabled: routine.reminderEnabled))
                                .font(.subheadline)
                                .foregroundStyle(NextCueStyle.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(isLocked ? "Opens Next Cue Pro options" : "Opens routine settings")

                if !isLocked {
                    Button(action: start) {
                        Image(systemName: isRunning ? "arrow.right" : "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(NextCueStyle.onAccent)
                            .frame(width: 44, height: 44)
                            .background(NextCueStyle.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRunning ? "Return to \(routine.name)" : "Start \(routine.name)")
                }
            }
        }
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
