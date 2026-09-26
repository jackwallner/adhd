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
    @AppStorage("nextcue.reviewPromptHandled") private var reviewPromptHandled = false
    @AppStorage(NextCuePreferences.stepTimerKey) private var showsStepTimer = true
    @AppStorage(NextCuePreferences.keepAwakeKey) private var keepsScreenAwake = true

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
            .sheet(isPresented: $showNewRoutine) { RoutineSetupView() }
        }
        .tint(NextCueStyle.accent)
        .sensoryFeedback(.success, trigger: doneCount)
        .sensoryFeedback(.selection, trigger: moveCount)
        .onAppear {
            trackedRunID = routines.activeRun?.id ?? (NextCueDebugLaunch.screen == "complete" ? routines.completions.last?.runID : nil)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StepTrack(run: run)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 8) {
                            Text("STEP \(run.currentStepIndex + 1) OF \(run.steps.count)")
                                .font(.caption.weight(.bold))
                                .tracking(1.05)
                                .foregroundStyle(NextCueStyle.accent)
                            if run.isShortVersion {
                                Label("Short version", systemImage: "leaf")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NextCueStyle.secondary)
                            }
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(step.name)
                                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
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
                    }
                    .padding(23)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(NextCueStyle.line.opacity(0.7), lineWidth: 1)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: run.nextStep == nil ? "flag.checkered" : "arrow.turn.down.right")
                            .accessibilityHidden(true)
                        Text(run.nextStep.map { "Next: \($0.name)" } ?? "Last step. Almost there.")
                            .lineLimit(2)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NextCueStyle.secondary)
                    .padding(.horizontal, 4)

                    if run.isPaused {
                        Label("Paused. Your place is saved.", systemImage: "pause.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NextCueStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls(run) }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast) { perform(.back) }
                        .padding(.bottom, run.isPaused ? 104 : 168)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func controls(_ run: RoutineRun) -> some View {
        VStack(spacing: 6) {
            if run.isPaused {
                Button {
                    if !routines.resumeRun() { showRoutineError = true }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
            } else {
                Button { perform(.done) } label: {
                    Label(run.nextStep == nil ? "Done, finish routine" : "Done", systemImage: "checkmark")
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
                .accessibilityIdentifier("run.done")

                HStack(spacing: 0) {
                    if run.canDoLater {
                        Button { perform(.later) } label: {
                            Label("Do it later", systemImage: "arrow.uturn.down")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .accessibilityHint("Moves this step to the end of the routine")
                    }
                    Button { perform(.skip) } label: {
                        Label("Skip", systemImage: "forward")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .accessibilityLabel("Skip this step")
                    .accessibilityHint("Moves on without marking this step done")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NextCueStyle.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
            VStack(alignment: .leading, spacing: 18) {
                FinishMark()
                VStack(alignment: .leading, spacing: 6) {
                    Text(completion.isComplete ? "That’s a wrap." : "Nice going.")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(NextCueStyle.ink)
                    Text(finishMessage(completion))
                        .font(.body)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    StatTile(value: "\(completion.completedSteps) of \(completion.totalSteps)", label: "steps done")
                    StatTile(value: durationLabel(completion.durationSeconds), label: "active time")
                    StatTile(value: NextCueFormat.time(completion.completedAt), label: "finished")
                }

                Button("Done") { dismiss() }
                    .buttonStyle(NextCuePrimaryButtonStyle())
                    .padding(.top, 6)

                if routines.canUndoFinish(completion) {
                    Button {
                        withAnimation { _ = routines.undoFinish() }
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
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let minutes = Int((seconds / 60).rounded())
        return minutes < 1 ? "<1 min" : NextCueFormat.minutes(minutes)
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
            .accessibilityValue("\(Int(elapsed / 60)) minutes of about \(estimateMinutes)")
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
        Image(systemName: "checkmark")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(NextCueStyle.onAccent)
            .frame(width: 68, height: 68)
            .background(NextCueStyle.success, in: Circle())
            .scaleEffect(shown || reduceMotion ? 1 : 0.4)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}
