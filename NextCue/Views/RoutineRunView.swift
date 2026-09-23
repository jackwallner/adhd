import SwiftUI

struct RoutineRunView: View {
    @EnvironmentObject private var routines: RoutineStore
    @EnvironmentObject private var purchases: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    @State private var showFinishConfirmation = false
    @State private var showRoutineError = false
    @State private var showPaywall = false
    @State private var showNewRoutine = false
    @State private var wantsNewRoutine = false
    @State private var didFinish = false
    @State private var finishedEveryStep = false
    @State private var skippedStepCount = 0
    @State private var finishedRoutineName = ""
    @State private var completionMessage = ""
    @AppStorage("nextcue.reviewPromptHandled") private var reviewPromptHandled = false

    init() {
        let showCompletion = NextCueDebugLaunch.screen == "complete"
        _didFinish = State(initialValue: showCompletion)
        _finishedEveryStep = State(initialValue: showCompletion)
        _finishedRoutineName = State(initialValue: showCompletion ? NextCueDebugLaunch.sampleRoutineName : "")
        _completionMessage = State(initialValue: showCompletion
            ? "You finished the steps in \(NextCueDebugLaunch.sampleRoutineName). Come back to this routine whenever it fits."
            : "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if didFinish {
                    finishedView
                } else if let run = routines.activeRun {
                    runContent(run)
                } else {
                    unavailableView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NextCueStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        pauseAndClose()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .disabled(routines.activeRun == nil || didFinish)
                    .accessibilityHint("Pauses this run and returns to Today")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("More routine options")
                    .disabled(routines.activeRun == nil || didFinish)
                }
            }
            .confirmationDialog("Finish this routine now?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
                Button("Finish routine") { finishRun() }
                Button("Cancel run", role: .destructive) { cancelRun() }
                Button("Keep going", role: .cancel) { }
            } message: {
                Text("You can wrap up here or continue with the next step.")
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
    }

    @ViewBuilder
    private func runContent(_ run: RoutineRun) -> some View {
        if run.steps.indices.contains(run.currentStepIndex) {
            let step = run.steps[run.currentStepIndex]
            let isPaused = run.pausedAt != nil
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(run.routineName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NextCueStyle.secondary)
                        Text("One step at a time")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(NextCueStyle.ink)
                    }

                    progress(for: run)

                    NextCueCard(padding: 23) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text("STEP \(run.currentStepIndex + 1) OF \(run.steps.count)")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.05)
                                    .foregroundStyle(NextCueStyle.accent)
                                Spacer()
                                Label("About \(step.estimateMinutes) min", systemImage: "clock")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(NextCueStyle.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
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
                    }

                    if isPaused {
                        Label("Paused. Come back whenever you’re ready.", systemImage: "pause.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NextCueStyle.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    VStack(spacing: 10) {
                        Button {
                            if isPaused {
                                if !routines.resumeRun() { showRoutineError = true }
                            }
                            else { advance(skip: false) }
                        } label: {
                            Label(isPaused ? "Resume" : "Done with this step", systemImage: isPaused ? "play.fill" : "checkmark")
                        }
                        .buttonStyle(NextCuePrimaryButtonStyle())

                        if !isPaused {
                            Button("Skip this step") { advance(skip: true) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NextCueStyle.secondary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .accessibilityHint("Moves to the next step without marking this one done")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
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

    private func progress(for run: RoutineRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(run.currentStepIndex + 1), total: Double(max(run.steps.count, 1)))
                .tint(NextCueStyle.accent)
                .accessibilityLabel("Routine progress")
                .accessibilityValue("Step \(run.currentStepIndex + 1) of \(run.steps.count)")
            Text("\(run.steps.count - run.currentStepIndex) \(run.steps.count - run.currentStepIndex == 1 ? "step" : "steps") to go")
                .font(.caption.weight(.medium))
                .foregroundStyle(NextCueStyle.secondary)
        }
    }

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            NextCueIcon(symbol: "checkmark", tint: NextCueStyle.success)
            Text("That’s a wrap.")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(NextCueStyle.ink)
            Text(completionMessage)
                .font(.body)
                .foregroundStyle(NextCueStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }
                .buttonStyle(NextCuePrimaryButtonStyle())
                .padding(.top, 8)

            if finishedEveryStep && routines.completions.count == 1 && !purchases.isPro {
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
            } else if finishedEveryStep && routines.completions.count >= 2 && !reviewPromptHandled {
                reviewPrompt
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func advance(skip: Bool) {
        guard let run = routines.activeRun else { return }
        let isLast = run.currentStepIndex == run.steps.count - 1
        let advanced: Bool
        if skip {
            advanced = routines.skipCurrentStep()
            skippedStepCount += 1
        } else {
            advanced = routines.completeCurrentStep()
        }
        guard advanced else {
            showRoutineError = true
            return
        }
        if isLast {
            finishedRoutineName = run.routineName
            finishedEveryStep = !skip && skippedStepCount == 0
            completionMessage = finishedEveryStep
                ? "You finished the steps in \(run.routineName). Come back to this routine whenever it fits."
                : "You wrapped up \(run.routineName). You can pick it up again whenever you’re ready."
            didFinish = true
        }
    }

    private func finishRun() {
        guard let run = routines.activeRun else { return }
        finishedRoutineName = run.routineName
        guard let completion = routines.finishRun() else {
            showRoutineError = true
            return
        }
        finishedEveryStep = completion.isComplete
        completionMessage = finishedEveryStep
            ? "You finished the steps in \(run.routineName). Come back to this routine whenever it fits."
            : "You wrapped up \(run.routineName). You can pick it up again whenever you’re ready."
        didFinish = true
    }

    private func cancelRun() {
        guard routines.cancelRun() else {
            showRoutineError = true
            return
        }
        dismiss()
    }

    private func pauseAndClose() {
        guard routines.activeRun != nil else { return }
        guard routines.pauseRun() else {
            showRoutineError = true
            return
        }
        dismiss()
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

    private func presentRoutineEditorAfterPurchase() {
        guard wantsNewRoutine, purchases.isPro else { return }
        wantsNewRoutine = false
        showNewRoutine = true
    }
}
