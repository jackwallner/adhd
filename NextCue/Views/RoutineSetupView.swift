import SwiftUI
import UIKit
import UserNotifications

struct RoutineSetupView: View {
    @EnvironmentObject private var routines: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let routine: Routine?

    @State private var name: String
    @State private var steps: [RoutineSetupStep]
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var weekdays: Set<Int>
    @State private var selectedTemplate: RoutineStarterTemplate?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showSaveError = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var savedCount = 0
    @FocusState private var focusedStep: UUID?

    init(routine: Routine? = nil) {
        let debugTemplate = routine == nil && NextCueDebugLaunch.screen == "editor"
            ? RoutineStarterTemplate.morning
            : nil
        self.routine = routine
        _name = State(initialValue: routine?.name ?? debugTemplate?.title ?? "")
        _steps = State(initialValue: routine?.steps.map(RoutineSetupStep.init(step:))
            ?? debugTemplate?.setupSteps
            ?? [])
        _reminderEnabled = State(initialValue: routine?.reminderEnabled ?? debugTemplate?.hasReminder ?? false)
        _weekdays = State(initialValue: routine?.schedule.weekdays ?? Set(debugTemplate?.weekdays ?? [2, 3, 4, 5, 6]))

        let hour = routine?.schedule.hour ?? debugTemplate?.hour ?? 8
        let minute = routine?.schedule.minute ?? debugTemplate?.minute ?? 0
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        _reminderTime = State(initialValue: date)
        _selectedTemplate = State(initialValue: debugTemplate)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        steps.contains { !$0.trimmedName.isEmpty } &&
        (!reminderEnabled || !weekdays.isEmpty)
    }

    private var totalMinutes: Int {
        steps.filter { !$0.trimmedName.isEmpty }.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if routine == nil { templateSection }
                    nameSection
                    stepsSection
                    reminderSection
                    if routine != nil { deleteRoutineAction }
                    Text("Next Cue supports routine planning. It does not diagnose or treat ADHD or any health condition.")
                        .font(.footnote)
                        .foregroundStyle(NextCueStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NextCueStyle.background.ignoresSafeArea())
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedStep = nil; hideKeyboard() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(routine == nil ? "Save routine" : "Save changes") {
                    Task { await save() }
                }
                .buttonStyle(NextCuePrimaryButtonStyle())
                .disabled(!canSave || isSaving)
                .opacity(canSave ? 1 : 0.55)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(NextCueStyle.background)
            }
            .task { await refreshNotificationStatus() }
            .sensoryFeedback(.success, trigger: savedCount)
            .alert("Couldn’t update routine", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(routines.persistenceError ?? "Please try again.")
            }
            .confirmationDialog("Delete this routine?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete routine", role: .destructive, action: deleteRoutine)
                Button("Keep routine", role: .cancel) { }
            } message: {
                Text("This also removes its schedule. You can create another routine later.")
            }
        }
        .tint(NextCueStyle.accent)
    }

    // MARK: Sections

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose a starting point")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                Text("Use a template as-is or make it yours.")
                    .font(.subheadline)
                    .foregroundStyle(NextCueStyle.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RoutineStarterTemplate.allCases.filter { $0 != .blank }) { template in
                    templateButton(template)
                }
            }
            templateButton(.blank)
        }
    }

    private func templateButton(_ template: RoutineStarterTemplate) -> some View {
        let selected = selectedTemplate == template
        return Button { apply(template) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: template.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
                    .accessibilityHidden(true)
                Text(template.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(NextCueStyle.ink)
                    .multilineTextAlignment(.leading)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(NextCueStyle.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: template == .blank ? nil : 112, alignment: .topLeading)
            .padding(14)
            .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? NextCueStyle.accent : NextCueStyle.line, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NextCueSectionTitle(title: "Name your routine")
            NextCueCard(padding: 14) {
                TextField("For example, Morning start", text: $name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit { focusedStep = steps.first?.id }
                    .accessibilityLabel("Routine name")
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NextCueSectionTitle(
                title: "Your steps",
                trailing: steps.isEmpty ? nil : "about \(NextCueFormat.minutes(totalMinutes))"
            )
            ForEach($steps) { $step in
                let index = steps.firstIndex { $0.id == step.id } ?? 0
                StepEditorCard(
                    step: $step,
                    number: index + 1,
                    canMoveUp: index > 0,
                    canMoveDown: index < steps.count - 1,
                    canRemove: steps.count > 1,
                    focusedStep: $focusedStep,
                    onSubmit: { addStep(after: step.id) },
                    move: { offset in move(step.id, by: offset) },
                    remove: { removeStep(id: step.id) }
                )
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
                    return drop(dragged, onto: step.id)
                }
            }

            Button {
                addStep(after: steps.last?.id)
            } label: {
                Label("Add a step", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }

            Text("Tip: mark steps optional to get a short version for low-energy days. Hold the handle to reorder.")
                .font(.footnote)
                .foregroundStyle(NextCueStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NextCueSectionTitle(title: "Reminder")
            NextCueCard {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $reminderEnabled.animation()) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Remind me on a schedule")
                                .font(.system(.headline, design: .rounded).weight(.semibold))
                                .foregroundStyle(NextCueStyle.ink)
                            Text("You can start this routine any time.")
                                .font(.footnote)
                                .foregroundStyle(NextCueStyle.secondary)
                        }
                    }
                    .tint(NextCueStyle.accent)

                    if reminderEnabled {
                        DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .font(.subheadline.weight(.medium))
                            .accessibilityHint("Choose when this routine should appear in your day")

                        HStack(spacing: 7) {
                            ForEach(NextCueWeekday.ordered) { day in
                                let selected = weekdays.contains(day.rawValue)
                                Button {
                                    toggle(day)
                                } label: {
                                    Text(day.shortName)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(selected ? NextCueStyle.onAccent : NextCueStyle.ink)
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(selected ? NextCueStyle.accent : NextCueStyle.background, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(day.fullName)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }

                        reminderPermission
                    }
                }
            }
        }
    }

    private var deleteRoutineAction: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete routine", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
        }
        .accessibilityHint("Permanently removes this routine and its reminder")
    }

    @ViewBuilder
    private var reminderPermission: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Reminders are on", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(NextCueStyle.success)
        case .denied:
            VStack(alignment: .leading, spacing: 7) {
                Text("Notifications are off, so this reminder won’t appear. You can still start the routine anytime.")
                    .font(.footnote)
                    .foregroundStyle(NextCueStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NextCueStyle.accent)
            }
        default:
            Label("iOS will ask to allow reminders when you save.", systemImage: "bell.badge")
                .font(.footnote)
                .foregroundStyle(NextCueStyle.secondary)
        }
    }

    // MARK: Actions

    private func apply(_ template: RoutineStarterTemplate) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTemplate = template
            name = template == .blank ? "" : template.title
            steps = template.setupSteps
            reminderEnabled = template.hasReminder
            weekdays = Set(template.weekdays)
            reminderTime = Calendar.current.date(bySettingHour: template.hour, minute: template.minute, second: 0, of: .now) ?? .now
        }
        if template == .blank { focusedStep = steps.first?.id }
    }

    private func toggle(_ day: NextCueWeekday) {
        if weekdays.contains(day.rawValue) {
            weekdays.remove(day.rawValue)
        } else {
            weekdays.insert(day.rawValue)
        }
    }

    /// Return on a step adds the next one, so a whole routine can be typed without reaching for buttons.
    private func addStep(after id: UUID?) {
        let index = id.flatMap { id in steps.firstIndex { $0.id == id } }
        if let index, index < steps.count - 1, steps[index + 1].trimmedName.isEmpty {
            focusedStep = steps[index + 1].id
            return
        }
        if let index, steps[index].trimmedName.isEmpty {
            focusedStep = nil
            return
        }
        let step = RoutineSetupStep(name: "", details: "", minutes: 5)
        withAnimation(.easeOut(duration: 0.2)) {
            steps.insert(step, at: index.map { $0 + 1 } ?? steps.count)
        }
        focusedStep = step.id
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { steps.swapAt(index, target) }
    }

    private func drop(_ dragged: UUID, onto target: UUID) -> Bool {
        guard dragged != target,
              let from = steps.firstIndex(where: { $0.id == dragged }),
              let to = steps.firstIndex(where: { $0.id == target }) else { return false }
        withAnimation(.easeInOut(duration: 0.2)) {
            steps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        return true
    }

    private func removeStep(id: UUID) {
        guard steps.count > 1 else { return }
        withAnimation(.easeOut(duration: 0.2)) { steps.removeAll { $0.id == id } }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if reminderEnabled && notificationStatus == .notDetermined {
            _ = await ReminderService.requestAuthorization()
            await refreshNotificationStatus()
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let schedule = RoutineSchedule(
            hour: components.hour ?? 8,
            minute: components.minute ?? 0,
            weekdays: reminderEnabled ? weekdays : []
        )
        let savedRoutine = Routine(
            id: routine?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps.compactMap(\.routineStep),
            schedule: schedule,
            isEnabled: routine?.isEnabled ?? true,
            reminderEnabled: reminderEnabled
        )
        guard routines.saveRoutine(savedRoutine) else {
            showSaveError = true
            return
        }
        savedCount += 1
        dismiss()
    }

    private func deleteRoutine() {
        guard let routine, routines.deleteRoutine(id: routine.id) else {
            showSaveError = true
            return
        }
        dismiss()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }
}

private struct StepEditorCard: View {
    @Binding var step: RoutineSetupStep
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canRemove: Bool
    var focusedStep: FocusState<UUID?>.Binding
    let onSubmit: () -> Void
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        NextCueCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NextCueStyle.accent)
                        .frame(width: 26, height: 26)
                        .background(NextCueStyle.accentWash, in: Circle())
                        .accessibilityHidden(true)
                    TextField("Step name", text: $step.name)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .focused(focusedStep, equals: step.id)
                        .submitLabel(.next)
                        .onSubmit(onSubmit)
                        .accessibilityLabel("Step \(number) name")
                    Menu {
                        Button { move(-1) } label: { Label("Move up", systemImage: "arrow.up") }
                            .disabled(!canMoveUp)
                        Button { move(1) } label: { Label("Move down", systemImage: "arrow.down") }
                            .disabled(!canMoveDown)
                        Button { step.isOptional.toggle() } label: {
                            Label(step.isOptional ? "Keep in short version" : "Leave out of short version", systemImage: "leaf")
                        }
                        Button(role: .destructive, action: remove) { Label("Remove step", systemImage: "trash") }
                            .disabled(!canRemove)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(NextCueStyle.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Step \(number) options")
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NextCueStyle.secondary.opacity(0.7))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                        .draggable(step.id.uuidString) {
                            Text(step.name.isEmpty ? "Step \(number)" : step.name)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .padding(12)
                                .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityHidden(true)
                }

                TextField("A short note, if helpful", text: $step.details, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                    .foregroundStyle(NextCueStyle.secondary)
                    .padding(.leading, 36)
                    .accessibilityLabel("Step \(number) note, optional")

                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                    Stepper(value: $step.minutes, in: 1...90, step: 1) {
                        Text("\(step.minutes) min")
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .accessibilityLabel("Estimated time")
                    .accessibilityValue("\(step.minutes) minutes")
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { step.isOptional.toggle() }
                    } label: {
                        Label("Optional", systemImage: step.isOptional ? "leaf.fill" : "leaf")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(step.isOptional ? NextCueStyle.onAccent : NextCueStyle.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(step.isOptional ? NextCueStyle.accent : NextCueStyle.background, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Optional step")
                    .accessibilityValue(step.isOptional ? "On, left out of the short version" : "Off")
                    .accessibilityAddTraits(step.isOptional ? .isSelected : [])
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(NextCueStyle.secondary)
                .padding(.leading, 36)
            }
        }
        .accessibilityAction(named: "Move up") { if canMoveUp { move(-1) } }
        .accessibilityAction(named: "Move down") { if canMoveDown { move(1) } }
    }
}

private struct RoutineSetupStep: Identifiable {
    let id: UUID
    var name: String
    var details: String
    var minutes: Int
    var isOptional: Bool

    init(id: UUID = UUID(), name: String, details: String, minutes: Int, isOptional: Bool = false) {
        self.id = id
        self.name = name
        self.details = details
        self.minutes = minutes
        self.isOptional = isOptional
    }

    init(step: RoutineStep) {
        self.init(
            id: step.id,
            name: step.name,
            details: step.details ?? "",
            minutes: step.estimateMinutes,
            isOptional: step.isOptional
        )
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Blank steps are dropped on save instead of blocking it.
    var routineStep: RoutineStep? {
        guard !trimmedName.isEmpty else { return nil }
        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoutineStep(id: id, name: trimmedName, details: note.isEmpty ? nil : note, estimateMinutes: minutes, isOptional: isOptional)
    }
}

private enum RoutineStarterTemplate: String, CaseIterable, Identifiable {
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
        case .morning: "A gentle first few steps"
        case .outTheDoor: "Gather what you need and go"
        case .workStart: "Get from sitting down to started"
        case .evening: "Make tomorrow a little easier"
        case .blank: "Build your own, one step at a time"
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
