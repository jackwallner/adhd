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
    @State private var showSavedNotice = false
    @State private var showSaveError = false
    @State private var showDeleteConfirmation = false

    init(routine: Routine? = nil) {
        let debugTemplate = routine == nil && NextCueDebugLaunch.screen == "editor"
            ? RoutineStarterTemplate.morning
            : nil
        self.routine = routine
        _name = State(initialValue: routine?.name ?? debugTemplate?.title ?? "")
        _steps = State(initialValue: routine?.steps.map {
            RoutineSetupStep(id: $0.id, name: $0.name, details: $0.details ?? "", minutes: $0.estimateMinutes)
        } ?? debugTemplate?.steps.map {
            RoutineSetupStep(name: $0.name, details: $0.details, minutes: $0.minutes)
        } ?? [])
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
        !steps.isEmpty && steps.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
        (!reminderEnabled || !weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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
            .background(NextCueStyle.background.ignoresSafeArea())
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(routine == nil ? "Save routine" : "Save changes", action: save)
                    .buttonStyle(NextCuePrimaryButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.55)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(NextCueStyle.background)
            }
            .task { await refreshNotificationStatus() }
            .alert("Routine saved", isPresented: $showSavedNotice) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your routine is ready whenever you are.")
            }
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
                ForEach(RoutineStarterTemplate.allCases) { template in
                    Button { apply(template) } label: {
                        VStack(alignment: .leading, spacing: 10) {
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
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .padding(14)
                        .background(NextCueStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(selectedTemplate == template ? NextCueStyle.accent : NextCueStyle.line, lineWidth: selectedTemplate == template ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTemplate == template ? .isSelected : [])
                }
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NextCueSectionTitle(title: "Name your routine")
            NextCueCard(padding: 14) {
                TextField("For example, Morning start", text: $name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Routine name")
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NextCueSectionTitle(title: "Your steps", trailing: "\(steps.count)")
            ForEach($steps) { $step in
                NextCueCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(steps.firstIndex(where: { $0.id == step.id }).map { $0 + 1 } ?? 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NextCueStyle.accent)
                                .frame(width: 26, height: 26)
                                .background(NextCueStyle.accentWash, in: Circle())
                                .accessibilityHidden(true)
                            TextField("Step name", text: $step.name)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .accessibilityLabel("Step name")
                            Button(role: .destructive) {
                                removeStep(id: step.id)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.title3)
                                    .foregroundStyle(NextCueStyle.secondary)
                            }
                            .accessibilityLabel("Remove step")
                        }

                        TextField("A short note, if helpful", text: $step.details, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...3)
                            .foregroundStyle(NextCueStyle.secondary)
                            .padding(.leading, 36)
                            .accessibilityLabel("Step note, optional")

                        HStack(spacing: 7) {
                            Image(systemName: "clock")
                                .accessibilityHidden(true)
                            Text("About")
                            Stepper(value: $step.minutes, in: 1...90, step: 1) {
                                Text("\(step.minutes) min")
                                    .monospacedDigit()
                            }
                            .fixedSize()
                            .accessibilityLabel("Estimated time, \(step.minutes) minutes")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NextCueStyle.secondary)
                        .padding(.leading, 36)
                    }
                }
            }

            Button {
                steps.append(RoutineSetupStep(name: "", details: "", minutes: 5))
            } label: {
                Label("Add a step", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NextCueSectionTitle(title: "Reminder")
            NextCueCard {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $reminderEnabled) {
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
                            ForEach(NextCueWeekday.allCases) { day in
                                let selected = weekdays.contains(day.rawValue)
                                Button {
                                    toggle(day)
                                } label: {
                                    Text(day.shortName)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(selected ? .white : NextCueStyle.ink)
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(selected ? NextCueStyle.accent : NextCueStyle.background, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(day.fullName), \(selected ? "selected" : "not selected")")
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
        if notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral {
            Label("Reminders are allowed", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(NextCueStyle.success)
        } else if notificationStatus == .denied {
            VStack(alignment: .leading, spacing: 7) {
                Text("Notifications are off. You can still use your routine anytime.")
                    .font(.footnote)
                    .foregroundStyle(NextCueStyle.secondary)
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NextCueStyle.accent)
            }
        } else {
            Button {
                Task { await requestNotificationAccess() }
            } label: {
                Label("Allow reminder alerts", systemImage: "bell.badge")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NextCueStyle.accent)
            }
            .accessibilityHint("Shows Apple’s notification permission prompt")
        }
    }

    private func apply(_ template: RoutineStarterTemplate) {
        selectedTemplate = template
        name = template.title
        steps = template.steps.map { RoutineSetupStep(name: $0.name, details: $0.details, minutes: $0.minutes) }
        reminderEnabled = template.hasReminder
        weekdays = Set(template.weekdays)
        reminderTime = Calendar.current.date(bySettingHour: template.hour, minute: template.minute, second: 0, of: .now) ?? .now
    }

    private func toggle(_ day: NextCueWeekday) {
        if weekdays.contains(day.rawValue) {
            weekdays.remove(day.rawValue)
        } else {
            weekdays.insert(day.rawValue)
        }
    }

    private func removeStep(id: UUID) {
        guard steps.count > 1 else { return }
        steps.removeAll { $0.id == id }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let schedule = RoutineSchedule(
            hour: components.hour ?? 8,
            minute: components.minute ?? 0,
            weekdays: reminderEnabled ? weekdays : []
        )
        let savedRoutine = Routine(
            id: routine?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps.map { RoutineStep(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), details: $0.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.details.trimmingCharacters(in: .whitespacesAndNewlines), estimateMinutes: $0.minutes) },
            schedule: schedule,
            isEnabled: routine?.isEnabled ?? true,
            reminderEnabled: reminderEnabled
        )
        guard routines.saveRoutine(savedRoutine) else {
            showSaveError = true
            return
        }
        showSavedNotice = true
    }

    private func deleteRoutine() {
        guard let routine, routines.deleteRoutine(id: routine.id) else {
            showSaveError = true
            return
        }
        dismiss()
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }

    @MainActor
    private func requestNotificationAccess() async {
        let granted = await ReminderService.requestAuthorization()
        if granted { routines.refreshReminders() }
        await refreshNotificationStatus()
    }
}

private struct RoutineSetupStep: Identifiable {
    let id: UUID
    var name: String
    var details: String
    var minutes: Int

    init(id: UUID = UUID(), name: String, details: String, minutes: Int) {
        self.id = id
        self.name = name
        self.details = details
        self.minutes = minutes
    }
}

private enum RoutineStarterTemplate: String, CaseIterable, Identifiable {
    case morning
    case outTheDoor
    case evening
    case blank

    var id: Self { self }
    var title: String {
        switch self {
        case .morning: "Morning start"
        case .outTheDoor: "Get out the door"
        case .evening: "Evening reset"
        case .blank: "Start from scratch"
        }
    }
    var subtitle: String {
        switch self {
        case .morning: "A gentle first few steps"
        case .outTheDoor: "Gather what you need and go"
        case .evening: "Make tomorrow a little easier"
        case .blank: "Build your own, one step at a time"
        }
    }
    var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .outTheDoor: "figure.walk.departure"
        case .evening: "moon.stars"
        case .blank: "plus"
        }
    }
    var hour: Int { self == .evening ? 21 : 8 }
    var minute: Int { 0 }
    var hasReminder: Bool { self != .blank }
    var weekdays: [Int] { self == .evening ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6] }
    var steps: [(name: String, details: String, minutes: Int)] {
        switch self {
        case .morning:
            [("Get out of bed", "", 2), ("Get dressed", "", 8), ("Eat something", "Keep it simple", 10), ("Gather what I need", "", 4)]
        case .outTheDoor:
            [("Get dressed", "", 8), ("Pack my bag", "", 5), ("Get keys and wallet", "", 2), ("Put on shoes", "", 2)]
        case .evening:
            [("Put tomorrow’s clothes out", "", 4), ("Charge my phone", "", 1), ("Set out what I need", "", 5)]
        case .blank:
            [("Start with one small step", "You can add or change this", 5)]
        }
    }
}
