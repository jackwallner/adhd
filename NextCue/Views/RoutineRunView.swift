import SwiftUI
import UIKit

struct RoutineRunView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trackedRunID: UUID?
    @State private var showCancelConfirmation = false
    @State private var showRoutineError = false
    @State private var showPaywall = false
    @State private var showNewRoutine = false
    @State private var wantsNewRoutine = false
    @State private var toast: RunToast?
    @State private var doneCount = 0
    @State private var moveCount = 0
    /// The step shrunk to its smallest start. Matching by ID clears it as soon as the step changes.
    @State private var stuckStepID: UUID?
    /// The step the user got going on from its smallest start, for a word of encouragement.
    @State private var startedStepID: UUID?
    @State private var showSmallestPrompt = false
    @State private var smallestDraft = ""
    @AppStorage("nextcue.reviewPromptHandled") private var reviewPromptHandled = false
    @AppStorage(NextCuePreferences.stepTimerKey) private var showsStepTimer = true
    @AppStorage(NextCuePreferences.keepAwakeKey) private var keepsScreenAwake = true
    @ScaledMetric(relativeTo: .largeTitle) private var stepTitleSize: CGFloat = 40

    private var finishedCompletion: RoutineCompletion? {
        trackedRunID.flatMap { routines.completion(forRun: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completion = finishedCompletion, routines.activeRun?.id != trackedRunID {
                    finishedView(completion)
                        .transition(.opacity)
                } else if let run = routines.activeRun {
                    runContent(run)
                } else {
                    unavailableView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NextCueStyle.background.ignoresSafeArea())
            .toolbar { toolbarContent }
            .confirmationDialog("End this run without saving?", isPresented: $showCancelConfirmation, titleVisibility: .visible) {
                Button("End without saving", role: .destructive) { cancelRun() }
                Button("Keep going", role: .cancel) { }
            } message: {
                Text("Nothing from this run will be recorded. The routine itself stays as it is.")
            }
            .alert("Routine couldn’t be saved", isPresented: $showRoutineError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(routines.persistenceError ?? "Please try again.")
            }
            .sheet(isPresented: $showPaywall, onDismiss: presentRoutineEditorAfterPurchase) {
                NextCuePaywallView()
            }
            .sheet(isPresented: $showNewRoutine) { NewRoutineSheet() }
            .alert("Smallest start", isPresented: $showSmallestPrompt) {
                TextField("For example, Turn on the water", text: $smallestDraft)
                Button("Save", action: saveSmallestStart)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("What’s the tiniest move that gets this step going? You’ll see it here next time you’re stuck.")
            }
        }
        .tint(NextCueStyle.accent)
        .sensoryFeedback(.success, trigger: doneCount)
        .sensoryFeedback(.selection, trigger: moveCount)
        .onAppear {
            trackedRunID = routines.activeRun?.id ?? (NextCueDebugLaunch.screen == "complete" ? routines.completions.last?.runID : nil)
            if NextCueDebugLaunch.screen == "stuck" { stuckStepID = routines.activeRun?.currentStep?.id }
            updateIdleTimer()
        }
        .onChange(of: routines.activeRun?.id) { _, newID in
            if let newID { trackedRunID = newID }
        }
        .onChange(of: routines.activeRun?.isPaused) { _, _ in updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let run = routines.activeRun, finishedCompletion == nil || run.id != trackedRunID {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    pauseAndClose()
                } label: {
                    if run.isPaused {
                        Label("Close", systemImage: "xmark")
                    } else {
                        Label("Pause", systemImage: "pause.fill")
                    }
                }
                .accessibilityHint(run.isPaused ? "Returns to Today with this run saved" : "Pauses this run and returns to Today")
            }
            ToolbarItem(placement: .principal) {
                Text(run.routineName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(NextCueStyle.secondary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if run.canMoveBack {
                        Button { perform(.back) } label: { Label("Back a step", systemImage: "arrow.uturn.backward") }
                            .disabled(run.isPaused)
                    }
                    Button { finishRun() } label: { Label("Finish here", systemImage: "flag.checkered") }
                    Button(role: .destructive) { showCancelConfirmation = true } label: {
                        Label("End without saving", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                }
                .accessibilityLabel("More routine options")
            }
        }
    }

    // MARK: Run

    @ViewBuilder
    private func runContent(_ run: RoutineRun) -> some View {
        if let step = run.currentStep {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        runHeader(run)
                        Spacer(minLength: 32)
                        stepFocus(run: run, step: step)
                        Spacer(minLength: 32)
                        nextUp(run)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls(run) }
            // The toast sits at the top so it never hides the next step card.
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(toast: toast) { perform(.back) }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else {
            VStack(spacing: 18) {
                Text("You’ve reached the end")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Button("Finish routine", action: finishRun)
                    .buttonStyle(NextCuePrimaryButtonStyle())
            }
            .padding(24)
        }
    }

    private func runHeader(_ run: RoutineRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StepTrack(run: run)
            HStack(spacing: 8) {
                Text("STEP \(run.currentStepIndex + 1) OF \(run.steps.count)")
                    .font(.caption.weight(.bold))
                    .tracking(1.05)
                    .foregroundStyle(NextCueStyle.accent)
                    .contentTransition(.numericText())
                if run.isShortVersion {
                    Label("Short version", systemImage: "leaf")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NextCueStyle.secondary)
                }
                Spacer()
                Text("about \(NextCueFormat.minutes(RoutineEngine.remainingMinutes(for: run))) left")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(NextCueStyle.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func isStuck(on step: RoutineStep) -> Bool { stuckStepID == step.id }

    private func stepFocus(run: RoutineRun, step: RoutineStep) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if run.isPaused {
                Label("Paused. Your place is saved.", systemImage: "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NextCueStyle.warm)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(NextCueStyle.warmWash, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if startedStepID == step.id {
                Label("Nice start. Keep going.", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(NextCueStyle.accentWash, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if isStuck(on: step) {
                stuckFocus(step)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(step.name)
                        .font(.system(size: stepTitleSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(NextCueStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let details = step.details,
                       !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(details)
                            .font(.title3)
                            .foregroundStyle(NextCueStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .id(step.id)
                .transition(stepTransition)

                if showsStepTimer {
                    StepTimer(run: run, estimateMinutes: step.estimateMinutes)
                } else {
                    Label("About \(NextCueFormat.minutes(step.estimateMinutes))", systemImage: "clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NextCueStyle.secondary)
                }

                if !run.isPaused {
                    Button {
                        withAnimation(.snappy) { stuckStepID = step.id }
                    } label: {
                        Label("I’m stuck", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NextCueStyle.accent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(NextCueStyle.accentWash, in: Capsule())
                    }
                    .buttonStyle(NextCuePressableStyle())
                    .accessibilityHint("Shrinks this step to a tiny first move")
                    .accessibilityIdentifier("run.stuck")
                }
            }
        }
        .opacity(run.isPaused ? 0.55 : 1)
        .animation(.snappy, value: run.isPaused)
    }

    /// The step shrunk to one tiny move. Starting is the goal; finishing the step can come after.
    private func stuckFocus(_ step: RoutineStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JUST THIS")
                .font(.caption.weight(.bold))
                .tracking(1.05)
                .foregroundStyle(NextCueStyle.accent)
            Text(step.startCue ?? "Do ten seconds of it")
                .font(.system(size: stepTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(NextCueStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Part of \u{201C}\(step.name)\u{201D}. Stopping after is allowed.")
                .font(.title3)
                .foregroundStyle(NextCueStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if step.startCue == nil {
                    Button("Save a smaller start") {
                        smallestDraft = ""
                        showSmallestPrompt = true
                    }
                    .accessibilityHint("Saves a tiny first move for this step")
                }
                Button("Show the whole step") {
                    withAnimation(.snappy) { stuckStepID = nil }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NextCueStyle.accent)
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
        .id("stuck-\(step.id)")
    }

    private func nextUp(_ run: RoutineRun) -> some View {
        HStack(spacing: 12) {
            Image(systemName: run.nextStep == nil ? "flag.checkered" : "arrow.turn.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NextCueStyle.accent)
                .frame(width: 32, height: 32)
                .background(NextCueStyle.accentWash, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.nextStep == nil ? "Last step" : "Then")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NextCueStyle.secondary)
                Text(run.nextStep?.name ?? "Almost there.")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(NextCueStyle.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NextCueStyle.line.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func controls(_ run: RoutineRun) -> some View {
        VStack(spacing: 4) {
            if run.isPaused {
                Button {
                    withAnimation(.snappy) { if !routines.resumeRun() { showRoutineError = true } }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(NextCuePrimaryButtonStyle(height: 62))
            } else {
                if let step = run.currentStep, isStuck(on: step) {
                    Button { startedSmall(step) } label: {
                        Label("I started", systemImage: "arrow.right")
                    }
                    .buttonStyle(NextCuePrimaryButtonStyle(height: 62))
                    .accessibilityHint("Brings back the whole step")
                    .accessibilityIdentifier("run.started")
                } else {
                    Button { perform(.done) } label: {
                        Label(run.nextStep == nil ? "Done, finish routine" : "Done", systemImage: "checkmark")
                    }
                    .buttonStyle(NextCuePrimaryButtonStyle(height: 62))
                    .accessibilityIdentifier("run.done")
                }

                HStack(spacing: 0) {
                    if run.canDoLater {
                        Button { perform(.later) } label: {
                            Label("Do it later", systemImage: "arrow.uturn.down")
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .accessibilityHint("Moves this step to the end of the routine")
                    }
                    Button { perform(.skip) } label: {
                        Label("Skip", systemImage: "forward")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Skip this step")
                    .accessibilityHint("Moves on without marking this step done")
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NextCueStyle.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(NextCueStyle.background)
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    // MARK: Finished

    private func finishedView(_ completion: RoutineCompletion) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                FinishMark()
                    .padding(.top, 36)
                VStack(spacing: 8) {
                    Text(completion.isComplete ? "That’s a wrap." : "Nice going.")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(NextCueStyle.ink)
                    Text(finishMessage(completion))
                        .font(.body)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    StatTile(value: "\(completion.completedSteps) of \(completion.totalSteps)", label: "steps done")
                    StatTile(value: durationLabel(completion.durationSeconds), label: "active time")
                    StatTile(value: NextCueFormat.time(completion.completedAt), label: "finished")
                }

                if let next = laterToday(after: completion) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                            .foregroundStyle(NextCueStyle.accent)
                            .accessibilityHidden(true)
                        Text("Later today: **\(next.name)** at \(NextCueFormat.time(hour: next.schedule.hour, minute: next.schedule.minute))")
                            .foregroundStyle(NextCueStyle.ink)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(NextCueStyle.accentWash.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                }

                if routines.canUndoFinish(completion) {
                    Button {
                        withAnimation(.snappy) { _ = routines.undoFinish() }
                    } label: {
                        Label("Not quite done? Undo the last step", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                }

                if completion.isComplete && routines.completions.count == 1 && !purchases.isPro {
                    NextCueCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Want another routine for a different part of your day?")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(NextCueStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Your first routine stays free. Pro adds as many as you need.")
                                .font(.subheadline)
                                .foregroundStyle(NextCueStyle.secondary)
                            Button("Add another routine") {
                                wantsNewRoutine = true
                                showPaywall = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NextCueStyle.accent)
                            .padding(.top, 2)
                        }
                    }
                } else if completion.isComplete && routines.completions.count >= 2 && !reviewPromptHandled {
                    reviewPrompt
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Done") { dismiss() }
                .buttonStyle(NextCuePrimaryButtonStyle(height: 62))
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .background(NextCueStyle.background)
        }
    }

    private func finishMessage(_ completion: RoutineCompletion) -> String {
        if completion.isComplete && completion.isShortVersion {
            return "You did the short version of \(completion.routineName). On a low-energy day, that counts."
        }
        if completion.isComplete {
            return "Every step of \(completion.routineName), done."
        }
        return "You got through part of \(completion.routineName). Pick it up again whenever it fits."
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "\(max(1, Int(seconds))) sec" }
        return NextCueFormat.minutes(Int((seconds / 60).rounded()))
    }

    /// The next scheduled routine still to come today, so finishing one points to the next.
    private func laterToday(after completion: RoutineCompletion) -> Routine? {
        let unlocked = routines.routines.filter {
            !NextCueRoutineAccess.requiresPro(routineID: $0.id, routines: routines.routines, isPro: purchases.isPro)
        }
        let now = Date.now
        let nowMinute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        return TodayPlan(routines: unlocked, completions: routines.completions, now: now).routines.first {
            $0.id != completion.routineID && $0.isScheduled && $0.schedule.minuteOfDay > nowMinute
                && !routines.completedToday(for: $0.id)
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Text("No routine is running")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(NextCueStyle.ink)
            Button("Done") { dismiss() }
                .buttonStyle(NextCueSecondaryButtonStyle())
        }
        .padding(24)
    }

    private var reviewPrompt: some View {
        NextCueCard(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Is Next Cue helping your day?")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Button("Yes, I’d like to rate it") {
                    reviewPromptHandled = true
                    requestReview()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NextCueStyle.accent)
                Button("Send feedback") {
                    reviewPromptHandled = true
                    openURL(NextCueLinks.feedback)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NextCueStyle.secondary)
                Button("Maybe later") { reviewPromptHandled = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NextCueStyle.secondary)
            }
        }
    }

    // MARK: Actions

    private enum RunAction {
        case done
        case skip
        case later
        case back
    }

    private func perform(_ action: RunAction) {
        guard let run = routines.activeRun else { return }
        let stepName = run.currentStep?.name ?? ""
        stuckStepID = nil
        startedStepID = nil
        var saved = false
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)) {
            switch action {
            case .done: saved = routines.completeCurrentStep()
            case .skip: saved = routines.skipCurrentStep()
            case .later: saved = routines.doCurrentStepLater()
            case .back: saved = routines.moveBack()
            }
        }
        guard saved else {
            showRoutineError = true
            return
        }
        switch action {
        case .done:
            doneCount += 1
            showToast("Done: \(stepName)")
        case .skip:
            moveCount += 1
            showToast("Skipped: \(stepName)")
        case .later:
            moveCount += 1
            showToast("Moved to the end: \(stepName)")
        case .back:
            moveCount += 1
            withAnimation { toast = nil }
        }
    }

    /// Undo stays available for a few seconds after each step, for the tap that came too fast.
    private func showToast(_ message: String) {
        guard routines.activeRun != nil else { return }
        let next = RunToast(message: message)
        withAnimation(.easeOut(duration: 0.2)) { toast = next }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast?.id == next.id {
                withAnimation(.easeIn(duration: 0.2)) { toast = nil }
            }
        }
    }

    private func startedSmall(_ step: RoutineStep) {
        moveCount += 1
        withAnimation(.snappy) {
            stuckStepID = nil
            startedStepID = step.id
        }
    }

    private func saveSmallestStart() {
        guard let step = routines.activeRun?.currentStep,
              !smallestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !routines.setSmallestStart(smallestDraft, forStep: step.id) { showRoutineError = true }
    }

    private func finishRun() {
        guard routines.activeRun != nil else { return }
        guard routines.finishRun() != nil else {
            showRoutineError = true
            return
        }
        toast = nil
    }

    private func cancelRun() {
        guard routines.cancelRun() else {
            showRoutineError = true
            return
        }
        dismiss()
    }

    private func pauseAndClose() {
        guard let run = routines.activeRun else { return }
        guard run.isPaused || routines.pauseRun() else {
            showRoutineError = true
            return
        }
        dismiss()
    }

    private func updateIdleTimer() {
        let running = routines.activeRun.map { !$0.isPaused } ?? false
        UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake && running
    }

    private func presentRoutineEditorAfterPurchase() {
        guard wantsNewRoutine, purchases.isPro else { return }
        wantsNewRoutine = false
        showNewRoutine = true
    }
}

private struct RunToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
}

private struct ToastView: View {
    let toast: RunToast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NextCueStyle.background)
                .lineLimit(1)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(NextCueStyle.accentWash)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(NextCueStyle.ink, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
}

/// One segment per step: done, skipped, current, and still to come.
private struct StepTrack: View {
    let run: RoutineRun

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
                Capsule()
                    .fill(color(index: index, step: step))
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Routine progress")
        .accessibilityValue("\(run.completedStepCount) of \(run.steps.count) steps done")
    }

    private func color(index: Int, step: RoutineStep) -> Color {
        if index == run.currentStepIndex { return NextCueStyle.accent.opacity(0.45) }
        guard index < run.currentStepIndex else { return NextCueStyle.line }
        let outcome = run.history.last { $0.stepID == step.id }?.outcome
        return outcome == .done ? NextCueStyle.accent : NextCueStyle.warm.opacity(0.55)
    }
}

/// Time on this step against its estimate. It counts up and never warns: running long is information, not failure.
private struct StepTimer: View {
    let run: RoutineRun
    let estimateMinutes: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = RoutineEngine.stepElapsedSeconds(for: run, at: context.date)
            let estimate = TimeInterval(estimateMinutes * 60)
            let isOver = elapsed > estimate
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NextCueFormat.clock(elapsed))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(NextCueStyle.ink)
                        .contentTransition(.numericText())
                    Text(isOver ? "over the \(NextCueFormat.minutes(estimateMinutes)) guess, that’s fine" : "of about \(NextCueFormat.minutes(estimateMinutes))")
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.secondary)
                    Spacer()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NextCueStyle.line.opacity(0.7))
                        Capsule()
                            .fill(isOver ? NextCueStyle.warm : NextCueStyle.accent)
                            .frame(width: proxy.size.width * min(elapsed / max(estimate, 1), 1))
                    }
                }
                .frame(height: 5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time on this step")
            .accessibilityValue("\(NextCueFormat.minutes(Int(elapsed / 60))) of about \(NextCueFormat.minutes(estimateMinutes))")
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(NextCueStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(NextCueStyle.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct FinishMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(NextCueStyle.success.opacity(0.25), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(shown && !reduceMotion ? 1.12 : 0.8)
                .opacity(shown && !reduceMotion ? 0 : 1)
            Circle()
                .fill(NextCueStyle.success)
                .frame(width: 88, height: 88)
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(NextCueStyle.onAccent)
                .symbolEffect(.bounce, value: shown)
        }
        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { shown = true }
        }
        .accessibilityHidden(true)
    }
}
