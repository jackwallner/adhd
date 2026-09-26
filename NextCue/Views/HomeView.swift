import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter

    @State private var showNewRoutine = false
    @State private var showPaywall = false
    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let plan = TodayPlan(routines: routines.routines, completions: routines.completions, now: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introduction(now: context.date)
                        leadCard(plan: plan, now: context.date)
                        otherRoutines(plan: plan)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
                }
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
            .sheet(item: $editingRoutine) { RoutineSetupView(routine: $0) }
        }
    }

    private func introduction(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(NextCueStyle.accent)
            Text("What’s next?")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(NextCueStyle.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func leadCard(plan: TodayPlan, now: Date) -> some View {
        if let run = routines.activeRun {
            ResumeRoutineCard(run: run) {
                if run.isPaused { routines.resumeRun() }
                router.showRun = true
            }
        } else if let routine = plan.upNext {
            UpNextCard(
                routine: routine,
                isLocked: requiresPro(for: routine),
                now: now,
                start: { start(routine) },
                startShort: { start(routine, shortVersion: true) }
            )
            .contextMenu { menu(for: routine, isComplete: false) }
        } else if plan.routines.isEmpty {
            noRoutineForToday
        } else {
            finishedTodayCard
        }
    }

    @ViewBuilder
    private func otherRoutines(plan: TodayPlan) -> some View {
        let leadID = routines.activeRun?.routineID ?? plan.upNext?.id
        let offDay = plan.routines.isEmpty
        let others = (offDay ? routines.routines : plan.routines).filter { $0.id != leadID }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                NextCueSectionTitle(title: offDay ? "Your routines" : "Today")
                ForEach(others) { routine in
                    let isComplete = routines.completedToday(for: routine.id)
                    let isLocked = requiresPro(for: routine)
                    Button {
                        start(routine)
                    } label: {
                        RoutineTodayRow(
                            routine: routine,
                            isComplete: isComplete,
                            isLocked: isLocked,
                            isBlocked: routines.activeRun != nil,
                            showsDays: offDay
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isLocked && (isComplete || routines.activeRun != nil))
                    .contextMenu { menu(for: routine, isComplete: isComplete) }
                    .accessibilityHint(isLocked ? "Opens Next Cue Pro options" : isComplete ? "Done today" : "Starts this routine")
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for routine: Routine, isComplete: Bool) -> some View {
        if !requiresPro(for: routine) {
            if routines.activeRun == nil {
                Button { start(routine) } label: {
                    Label(isComplete ? "Run again" : "Start", systemImage: "play")
                }
                if routine.hasShortVersion {
                    Button { start(routine, shortVersion: true) } label: {
                        Label("Start short version", systemImage: "leaf")
                    }
                }
            }
            Button { editingRoutine = routine } label: { Label("Edit", systemImage: "pencil") }
        }
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
                     : "Any routine can still run today. Pick one below whenever it fits.")
                    .font(.body)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if routines.routines.isEmpty {
                    Button("Choose a starter routine", action: addRoutine)
                        .buttonStyle(NextCuePrimaryButtonStyle())
                }
            }
        }
    }

    private var finishedTodayCard: some View {
        NextCueCard(padding: 20) {
            HStack(alignment: .top, spacing: 13) {
                NextCueIcon(symbol: "checkmark", tint: NextCueStyle.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("That’s everything for today")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text("Your routines will be here when you need them again.")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func requiresPro(for routine: Routine) -> Bool {
        NextCueRoutineAccess.requiresPro(
            routineID: routine.id,
            routines: routines.routines,
            isPro: purchases.isPro
        )
    }
}

/// Leads with the literal first step: starting one small thing is easier than starting a routine.
private struct UpNextCard: View {
    let routine: Routine
    let isLocked: Bool
    let now: Date
    let start: () -> Void
    let startShort: () -> Void

    private var eyebrow: String {
        guard routine.isScheduled else { return "UP NEXT" }
        return "UP NEXT · \(NextCueFormat.time(hour: routine.schedule.hour, minute: routine.schedule.minute).uppercased())"
    }

    var body: some View {
        NextCueCard(padding: 21) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(NextCueStyle.accent)
                    Text(routine.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let first = routine.steps.first, !isLocked {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Just the first step")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                        Text(first.name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(NextCueStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NextCueStyle.accentWash.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }

                Button(action: start) {
                    Label(isLocked ? "See Pro options" : "Start routine", systemImage: isLocked ? "lock.fill" : "play.fill")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())

                if routine.hasShortVersion, !isLocked {
                    Button(action: startShort) {
                        HStack(spacing: 6) {
                            Image(systemName: "leaf")
                                .accessibilityHidden(true)
                            Text("Low energy? Short version: \(NextCueFormat.steps(routine.shortSteps.count)), \(NextCueFormat.minutes(routine.shortEstimatedMinutes))")
                                .multilineTextAlignment(.leading)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NextCueStyle.accent)
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Runs only the steps not marked optional")
                }
            }
        }
    }

    private var summary: String {
        let minutes = routine.estimatedMinutes
        let doneAround = NextCueFormat.time(now.addingTimeInterval(TimeInterval(minutes * 60)))
        return "\(NextCueFormat.steps(routine.steps.count)) · about \(NextCueFormat.minutes(minutes))\nStart now, done around \(doneAround)"
    }
}

private struct ResumeRoutineCard: View {
    let run: RoutineRun
    let resume: () -> Void

    var body: some View {
        NextCueCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(run.isPaused ? "PAUSED · READY WHEN YOU ARE" : "IN PROGRESS")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(NextCueStyle.accent)
                    Spacer()
                    Text("Step \(min(run.currentStepIndex + 1, run.steps.count)) of \(run.steps.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(NextCueStyle.secondary)
                }
                Text(run.routineName)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                if let currentStep = run.currentStep {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You were on")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                        Text(currentStep.name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(NextCueStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NextCueStyle.accentWash.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
                Button(action: resume) {
                    Label(run.isPaused ? "Resume routine" : "Return to routine", systemImage: "arrow.right")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
            }
        }
    }
}

private struct RoutineTodayRow: View {
    let routine: Routine
    let isComplete: Bool
    let isLocked: Bool
    let isBlocked: Bool
    var showsDays = false

    private var timeLabel: String {
        guard routine.isScheduled else { return "Anytime" }
        if showsDays { return NextCueSchedule.days(routine.schedule.weekdays) }
        return NextCueFormat.time(hour: routine.schedule.hour, minute: routine.schedule.minute)
    }

    var body: some View {
        NextCueCard(padding: 16) {
            HStack(spacing: 14) {
                Text(timeLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(isComplete ? NextCueStyle.secondary : NextCueStyle.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: 66, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(isComplete ? NextCueStyle.secondary : NextCueStyle.ink)
                        .strikethrough(isComplete, color: NextCueStyle.secondary)
                    Text("\(NextCueFormat.steps(routine.steps.count)) · about \(NextCueFormat.minutes(routine.estimatedMinutes))")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                }
                Spacer(minLength: 4)
                trailing
            }
        }
        .opacity(isBlocked && !isComplete && !isLocked ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if isLocked {
            Image(systemName: "lock.fill")
                .foregroundStyle(NextCueStyle.accent)
                .accessibilityLabel("Locked")
        } else if isComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(NextCueStyle.success)
                .accessibilityLabel("Done")
        } else {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(NextCueStyle.accent)
                .accessibilityHidden(true)
        }
    }
}
