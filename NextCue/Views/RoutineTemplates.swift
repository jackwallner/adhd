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
    case leaveHouse
    case workStart
    case dreadedTask
    case evening
    case bedtime
    case blank

    var id: Self { self }

    var title: String {
        switch self {
        case .morning: "Morning start"
        case .leaveHouse: "Leave the house"
        case .workStart: "Start work"
        case .dreadedTask: "Start a dreaded task"
        case .evening: "Evening reset"
        case .bedtime: "Bedtime"
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
        case .leaveHouse: "door.left.hand.open"
        case .workStart: "laptopcomputer"
        case .dreadedTask: "mountain.2"
        case .evening: "moon.stars"
        case .bedtime: "bed.double"
        case .blank: "plus"
        }
    }

    var hour: Int {
        switch self {
        case .evening: 20
        case .bedtime: 22
        case .workStart: 9
        default: 8
        }
    }

    var minute: Int { self == .leaveHouse ? 30 : 0 }
    /// A dreaded task has no set time, so it waits on Home as an anytime routine.
    var hasReminder: Bool { self != .blank && self != .dreadedTask }
    var weekdays: [Int] { self == .evening || self == .bedtime ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6] }
    var routineName: String { self == .blank ? "" : title }

    var setupSteps: [RoutineSetupStep] {
        steps.map {
            RoutineSetupStep(name: $0.name, details: $0.details, smallestStart: $0.smallest, minutes: $0.minutes, isOptional: $0.optional)
        }
    }

    private var steps: [(name: String, details: String, smallest: String, minutes: Int, optional: Bool)] {
        switch self {
        case .morning:
            [
                ("Get out of bed", "", "Sit up and put both feet on the floor", 2, false),
                ("Drink a glass of water", "", "Fill the glass", 1, false),
                ("Get dressed", "", "Put on one sock", 8, false),
                ("Make the bed", "Good enough is fine", "Pull the cover up", 3, true),
                ("Eat something", "Hungry or not", "Open the fridge", 10, false),
                ("Gather what I need", "", "Pick up your keys", 4, true),
            ]
        case .leaveHouse:
            [
                ("Grab my bag", "Packed the night before", "Look by the door", 1, false),
                ("Phone, keys, wallet", "", "Pat your pockets", 1, false),
                ("Take the trash out", "", "Pick up the bag", 2, true),
                ("Pack an umbrella", "Every day, rain or not", "Open the closet", 1, true),
                ("Shoes on", "", "Put on one shoe", 2, false),
                ("Lock the door", "", "Pull the door shut", 1, false),
            ]
        case .workStart:
            [
                ("Get a drink", "", "Stand up", 3, true),
                ("Clear the desk", "Just enough space to work", "Push everything to one side", 3, true),
                ("Pick the one first task", "The easiest one is fine", "Write one word for it", 2, false),
                ("Put my phone out of reach", "", "Turn it face down", 1, false),
                ("Open only what that task needs", "", "Open one window", 2, false),
                ("Work on it for 10 minutes", "Stopping after is allowed", "Do the first two minutes", 10, false),
            ]
        case .dreadedTask:
            [
                ("Name the task", "One sentence is enough", "Say it out loud", 1, false),
                ("Ask someone to work alongside", "A quiet call counts", "Text one person", 2, true),
                ("Get what it needs", "", "Open the file or pick up the tool", 2, false),
                ("Do the easiest part first", "", "Point at where it starts", 5, false),
                ("Keep going for 10 minutes", "Stopping after is allowed", "Do one more small piece", 10, true),
                ("Leave a note for next time", "Leave it open where you’ll see it", "Write one line", 1, true),
            ]
        case .evening:
            [
                ("Put tomorrow’s clothes out", "", "Pick a shirt", 4, false),
                ("Wash the dishes", "Just while the microwave runs", "Rinse one plate", 5, true),
                ("Tidy one surface", "", "Put away three things", 5, true),
                ("Pack tomorrow’s bag", "Leave it by the door", "Put your bag by the door", 5, false),
                ("Hang the trash on the door handle", "", "Tie the bag", 1, true),
            ]
        case .bedtime:
            [
                ("Charge my phone outside the bedroom", "", "Carry it to the hall", 1, false),
                ("Shower", "Three minutes counts", "Sit in the bathroom, clothes on", 5, true),
                ("Brush my teeth", "In the shower works", "Put toothpaste on the brush", 3, false),
                ("Lights out", "", "Turn off one light", 1, false),
            ]
        case .blank:
            [("", "", "", 5, false)]
        }
    }
}
