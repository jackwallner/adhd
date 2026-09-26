import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct NextCueWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

private enum Palette {
    static let background = Color(red: 0.106, green: 0.188, blue: 0.196)
    static let accent = Color(red: 0.49, green: 0.78, blue: 0.76)
    static let muted = Color.white.opacity(0.62)
}

/// Lock Screen and Dynamic Island for a run: the step, how long it has been going, and Done.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRun(name: context.attributes.routineName, state: context.state)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(state.stepNumber)/\(state.stepCount)")
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Palette.accent)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StepClock(state: state)
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.isFinished ? "All done" : state.stepName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(state.isFinished ? "Nice work." : state.nextStepName.map { "Next: \($0)" } ?? "Last step")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        RunButton(state: state)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: state.isFinished ? "checkmark" : state.isPaused ? "pause.fill" : "checklist")
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                StepClock(state: state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: state.isFinished ? "checkmark" : state.isPaused ? "pause.fill" : "checklist")
                    .foregroundStyle(Palette.accent)
            }
        }
    }
}

private struct LockScreenRun: View {
    let name: String
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.isFinished {
            finished
        } else {
            running
        }
    }

    private var finished: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.background)
                .frame(width: 40, height: 40)
                .background(Palette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("All done. Nice work.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(name.uppercased()) · STEP \(state.stepNumber) OF \(state.stepCount)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                Spacer(minLength: 6)
                StepClock(state: state)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.stepName)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(state.isPaused ? "Paused. Pick it up when you’re ready." : state.nextStepName.map { "Next: \($0)" } ?? "Last step")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                RunButton(state: state)
            }

            if !state.isPaused {
                ProgressView(timerInterval: state.stepStartedAt...state.estimateEndsAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Palette.accent)
            }
        }
        .padding(16)
    }
}

/// Time on the current step, counting up. Paused runs show the estimate instead.
private struct StepClock: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.isFinished {
            Text("Done")
        } else if state.isPaused {
            Text("Paused")
        } else {
            Text(state.stepStartedAt, style: .timer)
        }
    }
}

private struct RunButton: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isFinished {
                EmptyView()
            } else if state.isPaused {
                Button(intent: ResumeRunIntent()) { label("Resume", symbol: "play.fill") }
            } else {
                Button(intent: CompleteStepIntent()) { label("Done", symbol: "checkmark") }
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Palette.accent, in: Capsule())
    }
}
