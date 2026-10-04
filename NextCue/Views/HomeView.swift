import SwiftUI

/// The one screen: what to do now, the rest of today, and every other routine.
struct HomeView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @EnvironmentObject private var router: NextCueRouter

    @State private var sheet: HomeSheet?
    @State private var wantsNewRoutine = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if routines.routines.isEmpty {
                            welcome(now: context.date)
                        } else {
                            content(now: context.date)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                    .animation(.snappy, value: routines.routines)
                    .animation(.snappy, value: routines.activeRun?.id)
                }
            }
            .background(NextCueStyle.background.ignoresSafeArea())
            .toolbar { toolbar }
            .sheet(item: $sheet, onDismiss: openEditorAfterPurchase) { sheet in
                switch sheet {
                case .newRoutine(let template): NewRoutineSheet(template: template)
                case .edit(let routine): NavigationStack { RoutineSetupView(routine: routine) }.tint(NextCueStyle.accent)
                case .paywall: NextCuePaywallView()
                case .settings: SettingsView()
                }
            }
        }
        .onChange(of: router.todayRequest) { _, _ in sheet = nil }
        .onAppear(perform: openDebugSheet)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        if !routines.routines.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addRoutine) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add routine")
            }
        }
    }

    // MARK: First launch

    private func welcome(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow(now)
                Text("One step at a time.")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(NextCueStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Next Cue shows you the next small thing to do, so getting started is easier. Pick a routine to begin. You can change every step.")
                    .font(.body)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RoutineTemplateList { sheet = .newRoutine($0) }
        }
    }

    // MARK: Today

    @ViewBuilder
    private func content(now: Date) -> some View {
        let plan = TodayPlan(routines: routines.routines, completions: routines.completions, now: now)
        let lead = TodayPlan(routines: unlockedRoutines, completions: routines.completions, now: now).upNext
        let leadID = routines.activeRun?.routineID ?? lead?.id
        let todayIDs = Set(plan.routines.map(\.id))
        let laterToday = plan.routines.filter { $0.id != leadID }
        let otherDays = routines.routines.filter { !todayIDs.contains($0.id) && $0.id != leadID }

        VStack(alignment: .leading, spacing: 10) {
            eyebrow(now)
            Text("What’s next?")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(NextCueStyle.ink)
                .accessibilityAddTraits(.isHeader)
        }

        leadCard(lead: lead, offDay: plan.routines.isEmpty, now: now)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

        if !laterToday.isEmpty {
            section(title: "Today", routines: laterToday, showsDays: false)
        }
        if !otherDays.isEmpty {
            section(title: plan.routines.isEmpty ? "Your routines" : "Other days", routines: otherDays, showsDays: true)
        }
        if routines.routines.contains(where: requiresPro) {
            Text("Your first routine is always free. The others need Next Cue Pro.")
                .font(.footnote)
                .foregroundStyle(NextCueStyle.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func eyebrow(_ now: Date) -> some View {
        Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(NextCueStyle.accent)
    }

    @ViewBuilder
    private func leadCard(lead: Routine?, offDay: Bool, now: Date) -> some View {
        if let run = routines.activeRun {
            ResumeRoutineCard(run: run) {
                if run.isPaused { routines.resumeRun() }
                router.showRun = true
            }
        } else if let lead {
            UpNextCard(
                routine: lead,
                now: now,
                start: { start(lead) },
                startShort: { start(lead, shortVersion: true) },
                edit: { sheet = .edit(lead) }
            )
        } else if offDay {
            NoticeCard(
                symbol: "sun.max",
                tint: NextCueStyle.accent,
                title: "Nothing scheduled today",
                message: "Any routine can still run. Tap play on one below whenever it fits."
            )
        } else {
            NoticeCard(
                symbol: "checkmark",
                tint: NextCueStyle.success,
                title: "That’s everything for today",
                message: "Your routines will be here when you need them again."
            )
        }
    }

    private func section(title: String, routines list: [Routine], showsDays: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NextCueSectionTitle(title: title)
            ForEach(list) { routine in
                RoutineRow(
                    routine: routine,
                    isComplete: routines.completedToday(for: routine.id),
                    isLocked: requiresPro(routine),
                    canStart: routines.activeRun == nil,
                    showsDays: showsDays,
                    open: { open(routine) },
                    start: { start(routine) }
                )
                .contextMenu { menu(for: routine) }
            }
        }
    }

    @ViewBuilder
    private func menu(for routine: Routine) -> some View {
        if !requiresPro(routine) {
            if routines.activeRun == nil {
                Button { start(routine) } label: {
                    Label(routines.completedToday(for: routine.id) ? "Run again" : "Start", systemImage: "play")
                }
                if routine.hasShortVersion {
                    Button { start(routine, shortVersion: true) } label: {
                        Label("Start short version", systemImage: "leaf")
                    }
                }
            }
            Button { sheet = .edit(routine) } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    // MARK: Actions

    private var unlockedRoutines: [Routine] {
        routines.routines.filter { !requiresPro($0) }
    }

    private func open(_ routine: Routine) {
        sheet = requiresPro(routine) ? .paywall : .edit(routine)
    }

    private func addRoutine() {
        guard routines.routines.isEmpty || purchases.isPro else {
            wantsNewRoutine = true
            sheet = .paywall
            return
        }
        sheet = .newRoutine(nil)
    }

    private func openEditorAfterPurchase() {
        guard wantsNewRoutine else { return }
        wantsNewRoutine = false
        if purchases.isPro { sheet = .newRoutine(nil) }
    }

    private func start(_ routine: Routine, shortVersion: Bool = false) {
        let outcome = RoutineLauncher.start(
            routine,
            shortVersion: shortVersion,
            routines: routines,
            isPro: purchases.isPro,
            router: router
        )
        if outcome == .needsPro { sheet = .paywall }
    }

    private func requiresPro(_ routine: Routine) -> Bool {
        NextCueRoutineAccess.requiresPro(
            routineID: routine.id,
            routines: routines.routines,
            isPro: purchases.isPro
        )
    }

    private func openDebugSheet() {
        switch NextCueDebugLaunch.screen {
        case "editor": sheet = .newRoutine(.morning)
        case "settings": sheet = .settings
        default: break
        }
    }
}

private enum HomeSheet: Identifiable {
    case newRoutine(RoutineStarterTemplate?)
    case edit(Routine)
    case paywall
    case settings

    var id: String {
        switch self {
        case .newRoutine(let template): "new-\(template?.rawValue ?? "picker")"
        case .edit(let routine): "edit-\(routine.id)"
        case .paywall: "paywall"
        case .settings: "settings"
        }
    }
}

/// Leads with the literal first step: starting one small thing is easier than starting a routine.
private struct UpNextCard: View {
    let routine: Routine
    let now: Date
    let start: () -> Void
    let startShort: () -> Void
    let edit: () -> Void

    /// A routine whose time passed long ago drops the time, so the card reads as an option and not as late.
    private var eyebrow: String {
        guard routine.isScheduled else { return "UP NEXT" }
        let calendar = Calendar.current
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard nowMinute - routine.schedule.minuteOfDay <= TodayPlan.dueWindowMinutes else { return "STILL OPEN TODAY" }
        return "UP NEXT · \(NextCueFormat.time(hour: routine.schedule.hour, minute: routine.schedule.minute).uppercased())"
    }

    var body: some View {
        NextCueCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow)
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(NextCueStyle.accent)
                        Text(routine.name)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(NextCueStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(NextCueStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Menu {
                        if routine.hasShortVersion {
                            Button(action: startShort) { Label("Start short version", systemImage: "leaf") }
                        }
                        Button(action: edit) { Label("Edit routine", systemImage: "pencil") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                            .frame(width: 36, height: 36)
                            .background(NextCueStyle.background, in: Circle())
                    }
                    .accessibilityLabel("More options for \(routine.name)")
                }

                if let first = routine.steps.first {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Just the first step")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                        Text(first.name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(NextCueStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let cue = first.startCue {
                            Text("Even smaller: \(cue)")
                                .font(.subheadline)
                                .foregroundStyle(NextCueStyle.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NextCueStyle.accentWash.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }

                Button(action: start) {
                    Label("Start routine", systemImage: "play.fill")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())

                if routine.hasShortVersion {
                    Button(action: startShort) {
                        HStack(spacing: 6) {
                            Image(systemName: "leaf")
                                .accessibilityHidden(true)
                            Text("Low energy? Short version: \(NextCueFormat.steps(routine.shortSteps.count)), \(NextCueFormat.minutes(routine.shortEstimatedMinutes))")
                                .multilineTextAlignment(.leading)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NextCueStyle.accent)
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Runs only the steps not marked optional")
                }
            }
        }
    }

    private var summary: String {
        "\(NextCueFormat.steps(routine.steps.count)) · about \(NextCueFormat.minutes(routine.estimatedMinutes))"
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
                ProgressView(value: run.progress)
                    .tint(NextCueStyle.accent)
                    .accessibilityLabel("Routine progress")
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

private struct NoticeCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        NextCueCard(padding: 20) {
            HStack(alignment: .top, spacing: 14) {
                NextCueIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(NextCueStyle.ink)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tapping the row opens the routine; the play button starts it.
private struct RoutineRow: View {
    let routine: Routine
    let isComplete: Bool
    let isLocked: Bool
    let canStart: Bool
    let showsDays: Bool
    let open: () -> Void
    let start: () -> Void

    private var timeLabel: String {
        guard routine.isScheduled else { return "Anytime" }
        if showsDays { return NextCueSchedule.days(routine.schedule.weekdays) }
        return NextCueFormat.time(hour: routine.schedule.hour, minute: routine.schedule.minute)
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(isComplete ? NextCueStyle.secondary : NextCueStyle.ink)
                        .multilineTextAlignment(.leading)
                    Text("\(timeLabel) · \(NextCueFormat.steps(routine.steps.count)), \(NextCueFormat.minutes(routine.estimatedMinutes))")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 56)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NextCueStyle.line.opacity(0.7), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NextCuePressableStyle())
        .accessibilityLabel("\(routine.name), \(timeLabel), \(NextCueFormat.steps(routine.steps.count))\(isComplete ? ", done today" : "")")
        .accessibilityHint(isLocked ? "Opens Next Cue Pro options" : "Opens the routine to edit")
        .overlay(alignment: .trailing) { trailing.padding(.trailing, 14) }
    }

    @ViewBuilder
    private var trailing: some View {
        if isLocked {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(NextCueStyle.secondary)
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if isComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(NextCueStyle.success)
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Button(action: start) {
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(NextCueStyle.onAccent)
                    .frame(width: 44, height: 44)
                    .background(NextCueStyle.accent, in: Circle())
            }
            .buttonStyle(NextCuePressableStyle())
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.35)
            .accessibilityLabel("Start \(routine.name)")
        }
    }
}
