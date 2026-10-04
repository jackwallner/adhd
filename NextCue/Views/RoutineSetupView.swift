import SwiftUI
import UIKit
import UserNotifications

struct RoutineSetupView: View {
    @EnvironmentObject private var routines: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let routine: Routine?
    private let onClose: (() -> Void)?
    private let showsCancel: Bool
    private let initialDraft: RoutineDraft

    @State private var name: String
    @State private var steps: [RoutineSetupStep]
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var weekdays: Set<Int>
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showSaveError = false
    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var isSaving = false
    @State private var savedCount = 0
    @FocusState private var focus: SetupField?

    init(routine: Routine) {
        self.init(
            routine: routine,
            name: routine.name,
            steps: routine.steps.map(RoutineSetupStep.init(step:)),
            reminderEnabled: routine.reminderEnabled,
            hour: routine.schedule.hour,
            minute: routine.schedule.minute,
            weekdays: routine.schedule.weekdays.isEmpty ? [2, 3, 4, 5, 6] : routine.schedule.weekdays,
            showsCancel: true,
            onClose: nil
        )
    }

    init(template: RoutineStarterTemplate, showsCancel: Bool = true, onClose: (() -> Void)? = nil) {
        self.init(
            routine: nil,
            name: template.routineName,
            steps: template.setupSteps,
            reminderEnabled: template.hasReminder,
            hour: template.hour,
            minute: template.minute,
            weekdays: Set(template.weekdays),
            showsCancel: showsCancel,
            onClose: onClose
        )
    }

    private init(
        routine: Routine?,
        name: String,
        steps: [RoutineSetupStep],
        reminderEnabled: Bool,
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        showsCancel: Bool,
        onClose: (() -> Void)?
    ) {
        self.routine = routine
        self.onClose = onClose
        self.showsCancel = showsCancel
        let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        initialDraft = RoutineDraft(name: name, steps: steps, reminderEnabled: reminderEnabled, hour: hour, minute: minute, weekdays: weekdays)
        _name = State(initialValue: name)
        _steps = State(initialValue: steps.isEmpty ? [RoutineSetupStep(name: "", details: "", minutes: 5)] : steps)
        _reminderEnabled = State(initialValue: reminderEnabled)
        _reminderTime = State(initialValue: time)
        _weekdays = State(initialValue: weekdays)
    }

    private var draft: RoutineDraft {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        return RoutineDraft(
            name: name,
            steps: steps,
            reminderEnabled: reminderEnabled,
            hour: components.hour ?? 8,
            minute: components.minute ?? 0,
            weekdays: weekdays
        )
    }

    private var hasChanges: Bool { draft != initialDraft }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        steps.contains { !$0.trimmedName.isEmpty } &&
        (!reminderEnabled || !weekdays.isEmpty)
    }

    private var totalMinutes: Int {
        steps.filter { !$0.trimmedName.isEmpty }.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        List {
            nameSection
            stepsSection
            reminderSection
            if routine != nil { deleteSection }
            Section {} footer: {
                Text("Next Cue supports routine planning. It does not diagnose or treat ADHD or any health condition.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(22)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(NextCueStyle.background.ignoresSafeArea())
        .navigationTitle(routine == nil ? "New routine" : "Edit routine")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasChanges)
        .toolbar { toolbar }
        .task {
            await refreshNotificationStatus()
            if routine == nil && name.isEmpty {
                try? await Task.sleep(for: .milliseconds(450))
                focus = .name
            }
        }
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
            Text("This also removes its reminder.")
        }
        .confirmationDialog("Discard your changes?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive, action: close)
            Button("Keep editing", role: .cancel) { }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsCancel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges { showDiscardConfirmation = true } else { close() }
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(routine == nil ? "Save" : "Done") {
                Task { await save() }
            }
            .fontWeight(.semibold)
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("setup.save")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
                .fontWeight(.semibold)
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("For example, Morning start", text: $name)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(NextCueStyle.ink)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = steps.first.map { .step($0.id) } }
                .accessibilityLabel("Routine name")
                .listRowBackground(NextCueStyle.surface)
        } header: {
            Text("Name")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach($steps) { $step in
                StepRow(
                    step: $step,
                    number: (steps.firstIndex { $0.id == step.id } ?? 0) + 1,
                    focus: $focus,
                    onSubmit: { addStep(after: step.id) }
                )
                .listRowBackground(NextCueStyle.surface)
                .deleteDisabled(steps.count == 1)
            }
            .onMove { from, to in
                withAnimation(.snappy) { steps.move(fromOffsets: from, toOffset: to) }
            }
            .onDelete { offsets in
                guard steps.count > offsets.count else { return }
                withAnimation(.snappy) { steps.remove(atOffsets: offsets) }
            }

            Button {
                addStep(after: steps.last?.id)
            } label: {
                Label("Add a step", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
            }
            .listRowBackground(NextCueStyle.surface)
        } header: {
            HStack {
                Text("Steps")
                Spacer()
                if totalMinutes > 0 {
                    Text("about \(NextCueFormat.minutes(totalMinutes))")
                        .textCase(nil)
                        .monospacedDigit()
                }
            }
        } footer: {
            Text("A smallest start is the tiny first move you’ll see when you tap I’m stuck. Optional steps are left out of the short version for low-energy days. Hold a step to drag it, or swipe left to delete.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: $reminderEnabled.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me")
                        .foregroundStyle(NextCueStyle.ink)
                    Text("It also sets when this routine shows up on Today.")
                        .font(.footnote)
                        .foregroundStyle(NextCueStyle.secondary)
                }
            }
            .tint(NextCueStyle.accent)
            .listRowBackground(NextCueStyle.surface)

            if reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .foregroundStyle(NextCueStyle.ink)
                    .listRowBackground(NextCueStyle.surface)
                    .accessibilityLabel("Reminder time")

                WeekdayPicker(weekdays: $weekdays)
                    .listRowBackground(NextCueStyle.surface)
            }
        } header: {
            Text("Reminder")
        } footer: {
            if reminderEnabled { reminderFooter }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete routine")
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(NextCueStyle.surface)
            .accessibilityHint("Permanently removes this routine and its reminder")
        }
    }

    @ViewBuilder
    private var reminderFooter: some View {
        if weekdays.isEmpty {
            Text("Pick at least one day.")
                .foregroundStyle(NextCueStyle.danger)
        } else {
            switch notificationStatus {
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are off for Next Cue, so this reminder won’t appear. The routine still shows on Today.")
                    Button("Turn on notifications") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
                }
            case .notDetermined:
                Text("\(NextCueSchedule.days(weekdays)) at \(NextCueFormat.time(reminderTime)). iOS will ask to allow notifications when you save.")
            default:
                Text("\(NextCueSchedule.days(weekdays)) at \(NextCueFormat.time(reminderTime)).")
            }
        }
    }

    // MARK: Actions

    /// Return on a step adds the next one, so a whole routine can be typed without reaching for buttons.
    private func addStep(after id: UUID?) {
        let index = id.flatMap { id in steps.firstIndex { $0.id == id } }
        if let index, index < steps.count - 1 {
            focus = .step(steps[index + 1].id)
            return
        }
        if let index, steps[index].trimmedName.isEmpty {
            focus = nil
            return
        }
        let step = RoutineSetupStep(name: "", details: "", minutes: 5)
        withAnimation(.snappy) {
            steps.insert(step, at: index.map { $0 + 1 } ?? steps.count)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            focus = .step(step.id)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        focus = nil
        if reminderEnabled && notificationStatus == .notDetermined {
            _ = await ReminderService.requestAuthorization()
            await refreshNotificationStatus()
        }
        let current = draft
        let schedule = RoutineSchedule(
            hour: current.hour,
            minute: current.minute,
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
        close()
    }

    private func deleteRoutine() {
        guard let routine, routines.deleteRoutine(id: routine.id) else {
            showSaveError = true
            return
        }
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }
}

private enum SetupField: Hashable {
    case name
    case step(UUID)
    case note(UUID)
    case smallest(UUID)
}

private struct RoutineDraft: Equatable {
    var name: String
    var steps: [RoutineSetupStep]
    var reminderEnabled: Bool
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
}

private struct StepRow: View {
    @Binding var step: RoutineSetupStep
    let number: Int
    var focus: FocusState<SetupField?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(NextCueStyle.accent)
                .frame(width: 26, height: 26)
                .background(NextCueStyle.accentWash, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                TextField("What’s the step?", text: $step.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(NextCueStyle.ink)
                    .focused(focus, equals: .step(step.id))
                    .submitLabel(.next)
                    .onSubmit(onSubmit)
                    .accessibilityLabel("Step \(number) name")
                TextField("Add a note", text: $step.details)
                    .font(.subheadline)
                    .foregroundStyle(NextCueStyle.secondary)
                    .focused(focus, equals: .note(step.id))
                    .submitLabel(.next)
                    .onSubmit(onSubmit)
                    .accessibilityLabel("Step \(number) note, optional")
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NextCueStyle.accent)
                        .accessibilityHidden(true)
                    TextField("Smallest start, for when you’re stuck", text: $step.smallestStart)
                        .font(.subheadline)
                        .foregroundStyle(NextCueStyle.ink)
                        .focused(focus, equals: .smallest(step.id))
                        .submitLabel(.next)
                        .onSubmit(onSubmit)
                        .accessibilityLabel("Step \(number) smallest start, optional")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        MinutesMenu(minutes: $step.minutes)
                        OptionalChip(isOptional: $step.isOptional)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MinutesMenu(minutes: $step.minutes)
                        OptionalChip(isOptional: $step.isOptional)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MinutesMenu: View {
    @Binding var minutes: Int

    private var options: [Int] {
        Array(Set([1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 45, 60, 90, minutes])).sorted()
    }

    var body: some View {
        Menu {
            Picker("About how long?", selection: $minutes) {
                ForEach(options, id: \.self) { Text(NextCueFormat.minutes($0)).tag($0) }
            }
        } label: {
            ChipLabel(title: NextCueFormat.minutes(minutes), symbol: "clock", isOn: false)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Estimated time")
        .accessibilityValue(NextCueFormat.minutes(minutes))
    }
}

private struct OptionalChip: View {
    @Binding var isOptional: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOptional.toggle() }
        } label: {
            ChipLabel(title: "Optional", symbol: isOptional ? "leaf.fill" : "leaf", isOn: isOptional)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: isOptional)
        .accessibilityLabel("Optional step")
        .accessibilityValue(isOptional ? "On, left out of the short version" : "Off")
        .accessibilityAddTraits(isOptional ? .isSelected : [])
    }
}

/// Built from an HStack because List rows render a plain Label as an icon only.
private struct ChipLabel: View {
    let title: String
    let symbol: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(title)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(isOn ? NextCueStyle.onAccent : NextCueStyle.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isOn ? NextCueStyle.accent : NextCueStyle.background, in: Capsule())
    }
}

private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NextCueWeekday.ordered) { day in
                let selected = weekdays.contains(day.rawValue)
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        if selected { weekdays.remove(day.rawValue) } else { weekdays.insert(day.rawValue) }
                    }
                } label: {
                    Text(day.shortName)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(selected ? NextCueStyle.onAccent : NextCueStyle.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? NextCueStyle.accent : NextCueStyle.background, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: weekdays)
    }
}

struct RoutineSetupStep: Identifiable, Equatable {
    let id: UUID
    var name: String
    var details: String
    var smallestStart: String
    var minutes: Int
    var isOptional: Bool

    init(id: UUID = UUID(), name: String, details: String, smallestStart: String = "", minutes: Int, isOptional: Bool = false) {
        self.id = id
        self.name = name
        self.details = details
        self.smallestStart = smallestStart
        self.minutes = minutes
        self.isOptional = isOptional
    }

    init(step: RoutineStep) {
        self.init(
            id: step.id,
            name: step.name,
            details: step.details ?? "",
            smallestStart: step.smallestStart ?? "",
            minutes: step.estimateMinutes,
            isOptional: step.isOptional
        )
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Blank steps are dropped on save instead of blocking it.
    var routineStep: RoutineStep? {
        guard !trimmedName.isEmpty else { return nil }
        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let smallest = smallestStart.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoutineStep(
            id: id,
            name: trimmedName,
            details: note.isEmpty ? nil : note,
            estimateMinutes: minutes,
            isOptional: isOptional,
            smallestStart: smallest.isEmpty ? nil : smallest
        )
    }
}
