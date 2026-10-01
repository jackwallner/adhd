import SwiftUI

/// New routines start here: pick a template, then land in the editor with it filled in.
struct NewRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [RoutineStarterTemplate] = []
    private let skipsPicker: Bool
    private let initialTemplate: RoutineStarterTemplate

    /// A template chosen before the sheet opened goes straight to the editor.
    init(template: RoutineStarterTemplate? = nil) {
        skipsPicker = template != nil
        initialTemplate = template ?? .blank
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if skipsPicker {
                    RoutineSetupView(template: initialTemplate, onClose: { dismiss() })
                } else {
                    picker
                }
            }
            .navigationDestination(for: RoutineStarterTemplate.self) { template in
                RoutineSetupView(template: template, showsCancel: false, onClose: { dismiss() })
            }
        }
        .tint(NextCueStyle.accent)
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick one close to what you need. You can change every step after.")
                    .font(.subheadline)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RoutineTemplateList { path.append($0) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(NextCueStyle.background.ignoresSafeArea())
        .navigationTitle("New routine")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

/// Starter templates as large rows, shared by first launch and the new routine sheet.
struct RoutineTemplateList: View {
    let pick: (RoutineStarterTemplate) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(RoutineStarterTemplate.allCases) { template in
                Button { pick(template) } label: { TemplateRow(template: template) }
                    .buttonStyle(NextCuePressableStyle())
                    .accessibilityIdentifier("template.\(template.rawValue)")
            }
        }
    }
}

private struct TemplateRow: View {
    let template: RoutineStarterTemplate

    var body: some View {
        HStack(spacing: 14) {
            NextCueIcon(symbol: template.symbol, tint: template == .blank ? NextCueStyle.secondary : NextCueStyle.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(NextCueStyle.secondary.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NextCueStyle.line.opacity(0.7), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum RoutineStarterTemplate: String, CaseIterable, Identifiable, Hashable {
    case morning
    case outTheDoor
    case workStart
    case evening
    case blank

    var id: Self { self }

    var title: String {
        switch self {
        case .morning: "Morning start"
        case .outTheDoor: "Get out the door"
        case .workStart: "Start work"
        case .evening: "Evening reset"
        case .blank: "Start from scratch"
        }
    }

    var subtitle: String {
        switch self {
        case .blank: "Build your own, one step at a time"
        default: "\(NextCueFormat.steps(steps.count)) · about \(NextCueFormat.minutes(steps.reduce(0) { $0 + $1.minutes }))"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .outTheDoor: "figure.walk.departure"
        case .workStart: "laptopcomputer"
        case .evening: "moon.stars"
        case .blank: "plus"
        }
    }

    var hour: Int {
        switch self {
        case .evening: 21
        case .workStart: 9
        default: 8
        }
    }

    var minute: Int { self == .outTheDoor ? 30 : 0 }
    var hasReminder: Bool { self != .blank }
    var weekdays: [Int] { self == .evening ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6] }
    var routineName: String { self == .blank ? "" : title }

    var setupSteps: [RoutineSetupStep] {
        steps.map { RoutineSetupStep(name: $0.name, details: $0.details, minutes: $0.minutes, isOptional: $0.optional) }
    }

    private var steps: [(name: String, details: String, minutes: Int, optional: Bool)] {
        switch self {
        case .morning:
            [
                ("Get out of bed", "Both feet on the floor", 2, false),
                ("Drink a glass of water", "", 1, false),
                ("Get dressed", "", 8, false),
                ("Make the bed", "Good enough is fine", 3, true),
                ("Eat something", "Keep it simple", 10, false),
                ("Gather what I need", "", 4, true),
            ]
        case .outTheDoor:
            [
                ("Get dressed", "", 8, false),
                ("Pack my bag", "", 5, false),
                ("Fill a water bottle", "", 2, true),
                ("Keys, wallet, phone", "Touch each one", 2, false),
                ("Put on shoes", "", 2, false),
            ]
        case .workStart:
            [
                ("Get a drink", "", 3, true),
                ("Clear the desk", "Just enough space to work", 3, true),
                ("Pick the one first task", "Write it down", 2, false),
                ("Put my phone out of reach", "", 1, false),
                ("Open only what that task needs", "", 2, false),
                ("Work on it for 10 minutes", "Stopping after is allowed", 10, false),
            ]
        case .evening:
            [
                ("Put tomorrow’s clothes out", "", 4, false),
                ("Tidy one surface", "", 5, true),
                ("Charge my phone", "", 1, false),
                ("Set out what I need", "", 5, true),
                ("Brush my teeth", "", 3, false),
            ]
        case .blank:
            [("", "", 5, false)]
        }
    }
}
