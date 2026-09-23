import SwiftUI
import UIKit

struct NextCueRootView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
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
            }
            if NextCueDebugLaunch.isPaywallSnapshot { showPaywallSnapshot = true }
        }
        .sheet(isPresented: $showPaywallSnapshot) { NextCuePaywallView() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            routines.refreshReminders()
            purchases.start()
        }
    }
}

struct RoutineLibraryView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService

    @State private var showNewRoutine = NextCueDebugLaunch.screen == "editor"
    @State private var showPaywall = false
    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if routines.routines.isEmpty {
                        emptyState
                    } else {
                        NextCueSectionTitle(title: "Your routines", trailing: "\(routines.routines.count)")
                        ForEach(routines.routines) { routine in
                            let isLocked = NextCueRoutineAccess.requiresPro(
                                routineID: routine.id,
                                routines: routines.routines,
                                isPro: purchases.isPro
                            )
                            Button {
                                if isLocked { showPaywall = true }
                                else { editingRoutine = routine }
                            } label: {
                                RoutineLibraryCard(routine: routine, isLocked: isLocked)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(isLocked ? "Opens Next Cue Pro options" : "Opens routine settings")
                        }

                        if !purchases.isPro {
                            Text("One routine is free. Pro adds unlimited routines.")
                                .font(.footnote)
                                .foregroundStyle(NextCueStyle.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
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
        .padding(.top, 36)
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

    var body: some View {
        NextCueCard {
            HStack(spacing: 14) {
                NextCueIcon(symbol: "checklist")
                VStack(alignment: .leading, spacing: 5) {
                    Text(routine.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text("\(routine.steps.count) \(routine.steps.count == 1 ? "step" : "steps") · \(NextCueSchedule.label(for: routine.schedule, remindersEnabled: routine.reminderEnabled))")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isLocked ? NextCueStyle.accent : NextCueStyle.secondary.opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum NextCueSchedule {
    static func label(for schedule: RoutineSchedule, remindersEnabled: Bool = true) -> String {
        guard remindersEnabled, !schedule.weekdays.isEmpty else { return "No reminder" }
        let hour = schedule.hour % 12 == 0 ? 12 : schedule.hour % 12
        let minute = schedule.minute < 10 ? "0\(schedule.minute)" : "\(schedule.minute)"
        let period = schedule.hour < 12 ? "AM" : "PM"
        let time = "\(hour):\(minute) \(period)"
        let days = schedule.weekdays.sorted().compactMap { weekday -> String? in
            guard let day = NextCueWeekday(rawValue: weekday) else { return nil }
            return String(day.fullName.prefix(3))
        }
        return days.count == 7 ? "Daily · \(time)" : "\(days.joined(separator: ", ")) · \(time)"
    }
}
