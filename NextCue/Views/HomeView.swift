import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService

    @State private var showNewRoutine = false
    @State private var showPaywall = false
    @State private var showRun = NextCueDebugLaunch.opensRoutineRun

    private var todaysRoutines: [Routine] {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return routines.routines.filter { routine in
            routine.isEnabled && (routine.schedule.weekdays.isEmpty || routine.schedule.weekdays.contains(weekday))
        }
    }

    private var upcomingRoutines: [Routine] {
        todaysRoutines.filter { !routines.completedToday(for: $0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction

                    if let activeRun = routines.activeRun {
                        ResumeRoutineCard(run: activeRun) {
                            if activeRun.pausedAt != nil { routines.resumeRun() }
                            showRun = true
                        }
                    }

                    if todaysRoutines.isEmpty {
                        noRoutineForToday
                    } else {
                        if routines.activeRun == nil, let first = upcomingRoutines.first {
                            let isLocked = requiresPro(for: first)
                            NextRoutineCard(routine: first, isLocked: isLocked) {
                                startOrReturn(to: first)
                            }
                        } else if routines.activeRun == nil, !todaysRoutines.isEmpty {
                            finishedTodayCard
                        }

                        let primaryID = routines.activeRun?.routineID ?? (routines.activeRun == nil ? upcomingRoutines.first?.id : nil)
                        let secondaryRoutines = todaysRoutines.filter { $0.id != primaryID }
                        if !secondaryRoutines.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                NextCueSectionTitle(title: routines.activeRun == nil ? "Also today" : "Today’s routines", trailing: "\(secondaryRoutines.count)")
                                ForEach(secondaryRoutines) { routine in
                                    let isLocked = requiresPro(for: routine)
                                    let isComplete = routines.completedToday(for: routine.id)
                                    Button {
                                        startOrReturn(to: routine)
                                    } label: {
                                        RoutineTodayCard(
                                            routine: routine,
                                            isComplete: isComplete,
                                            isCurrent: routines.activeRun?.routineID == routine.id,
                                            isLocked: isLocked
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!isLocked && (routines.activeRun != nil || isComplete))
                                    .accessibilityHint(isLocked ? "Opens Next Cue Pro options" : isComplete ? "Completed today" : routines.activeRun != nil ? "Return to the routine already in progress" : "Starts this routine")
                                }
                            }
                        }
                    }

                    Button(action: addRoutine) {
                        Label("Add a routine", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NextCueSecondaryButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(NextCueStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: addRoutine) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add routine")
                }
            }
            .sheet(isPresented: $showNewRoutine) { RoutineSetupView() }
            .sheet(isPresented: $showPaywall) { NextCuePaywallView() }
            .fullScreenCover(isPresented: $showRun) { RoutineRunView() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(NextCueStyle.accent)
            Text("What’s next?")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(NextCueStyle.ink)
            Text("One step at a time. Start whenever you’re ready.")
                .font(.body)
                .foregroundStyle(NextCueStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noRoutineForToday: some View {
        NextCueCard(padding: 22) {
            VStack(alignment: .leading, spacing: 15) {
                NextCueIcon(symbol: routines.routines.isEmpty ? "sparkles" : "sun.max")
                Text(routines.routines.isEmpty ? "Start with one routine" : "Nothing scheduled today")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Text(routines.routines.isEmpty
                     ? "Pick a starter routine and make it your own. You can change every step."
                     : "You can still start any routine from the Routines tab, or add one for today.")
                    .font(.body)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(routines.routines.isEmpty ? "Choose a starter routine" : "Add a routine", action: addRoutine)
                    .buttonStyle(NextCuePrimaryButtonStyle())
            }
        }
    }

    private var finishedTodayCard: some View {
        NextCueCard(padding: 20) {
            HStack(alignment: .top, spacing: 13) {
                NextCueIcon(symbol: "checkmark", tint: NextCueStyle.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text(upcomingRoutines.isEmpty ? "You’ve done enough for today" : "Ready for another step?")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text(upcomingRoutines.isEmpty
                         ? "Your routines will be here when you need them again."
                         : "Choose another routine when it fits.")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                }
            }
        }
    }

    private func addRoutine() {
        guard routines.routines.first?.id == nil || purchases.isPro else {
            showPaywall = true
            return
        }
        showNewRoutine = true
    }

    private func startOrReturn(to routine: Routine) {
        guard !requiresPro(for: routine) else {
            showPaywall = true
            return
        }
        if routines.activeRun != nil {
            showRun = true
            return
        }
        guard !routines.completedToday(for: routine.id) else { return }
        routines.startRun(routineID: routine.id)
        showRun = true
    }

    private func requiresPro(for routine: Routine) -> Bool {
        NextCueRoutineAccess.requiresPro(
            routineID: routine.id,
            routines: routines.routines,
            isPro: purchases.isPro
        )
    }
}

private struct NextRoutineCard: View {
    let routine: Routine
    let isLocked: Bool
    let start: () -> Void

    var body: some View {
        NextCueCard(padding: 21) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UP NEXT")
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(NextCueStyle.accent)
                        Text(routine.name)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(NextCueStyle.ink)
                    }
                    Spacer()
                    NextCueIcon(symbol: isLocked ? "lock.fill" : "arrow.right.circle.fill")
                }

                Text("\(routine.steps.count) \(routine.steps.count == 1 ? "step" : "steps") · \(NextCueSchedule.label(for: routine.schedule, remindersEnabled: routine.reminderEnabled))")
                    .font(.subheadline)
                    .foregroundStyle(NextCueStyle.secondary)

                Button(action: start) {
                    Label(isLocked ? "See Pro options" : "Start routine", systemImage: isLocked ? "lock.fill" : "play.fill")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
            }
        }
    }
}

private struct ResumeRoutineCard: View {
    let run: RoutineRun
    let resume: () -> Void

    private var currentStep: RoutineStep? {
        guard run.steps.indices.contains(run.currentStepIndex) else { return nil }
        return run.steps[run.currentStepIndex]
    }

    var body: some View {
        NextCueCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(run.pausedAt == nil ? "ROUTINE IN PROGRESS" : "READY WHEN YOU ARE")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(NextCueStyle.accent)
                    Spacer()
                    Image(systemName: run.pausedAt == nil ? "play.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(NextCueStyle.accent)
                        .accessibilityHidden(true)
                }
                Text(run.routineName)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                if let currentStep {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your next step")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NextCueStyle.secondary)
                        Text(currentStep.name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(NextCueStyle.ink)
                    }
                }
                Button(action: resume) {
                    Label(run.pausedAt == nil ? "Return to routine" : "Resume routine", systemImage: "arrow.right")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
            }
        }
    }
}

private struct RoutineTodayCard: View {
    let routine: Routine
    var isComplete = false
    var isCurrent = false
    var isLocked = false

    var body: some View {
        NextCueCard(padding: 16) {
            HStack(spacing: 13) {
                NextCueIcon(symbol: "checklist")
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text("\(routine.steps.count) \(routine.steps.count == 1 ? "step" : "steps") · \(NextCueSchedule.label(for: routine.schedule, remindersEnabled: routine.reminderEnabled))")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                }
                Spacer(minLength: 4)
                if isLocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NextCueStyle.accent)
                        .labelStyle(.titleAndIcon)
                } else if isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NextCueStyle.success)
                        .labelStyle(.titleAndIcon)
                } else if isCurrent {
                    Label("In progress", systemImage: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NextCueStyle.accent)
                        .labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NextCueStyle.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NextCueStyle.secondary.opacity(0.7))
                    .padding(.trailing, 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isComplete ? "Completed today" : isCurrent ? "Currently in progress" : "Starts this routine")
    }
}
