import Foundation
import UserNotifications
import os

@MainActor
protocol ReminderScheduling: AnyObject {
    func configure()
    func reschedule(
        routines: [Routine],
        completions: [RoutineCompletion],
        activeRun: RoutineRun?,
        now: Date
    )
}

@MainActor
final class ReminderService: NSObject, ReminderScheduling, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    nonisolated static let routineCategoryID = "NEXTCUE_ROUTINE"
    nonisolated static let nudgeCategoryID = "NEXTCUE_NUDGE"
    nonisolated static let startActionID = "NEXTCUE_START"
    nonisolated static let snoozeActionID = "NEXTCUE_SNOOZE"
    nonisolated static let doneActionID = "NEXTCUE_DONE"
    nonisolated static let pauseActionID = "NEXTCUE_PAUSE"

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "NextCue", category: "Reminders")
    private var rescheduleTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startActionID, title: "Start now", options: [.foreground])
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "In \(ReminderPlan.snoozeMinutes) minutes",
            options: []
        )
        let done = UNNotificationAction(identifier: Self.doneActionID, title: "Done, next step", options: [])
        let pause = UNNotificationAction(identifier: Self.pauseActionID, title: "Pause for now", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.routineCategoryID, actions: [start, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.nudgeCategoryID, actions: [done, pause], intentIdentifiers: [])
        ])
    }

    /// Call from a user initiated control. Scheduling never asks for permission by itself.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func reschedule(
        routines: [Routine],
        completions: [RoutineCompletion],
        activeRun: RoutineRun?,
        now: Date = .now
    ) {
        let reminders = ReminderPlan.reminders(
            routines: routines,
            completions: completions,
            activeRun: activeRun,
            now: now
        )
        let nudge = NextCuePreferences.stepNudges ? ReminderPlan.nudge(for: activeRun, now: now) : nil
        let settledRoutineIDs = Set(routines.map(\.id).filter {
            $0 == activeRun?.routineID ||
                RoutineEngine.hasCompletion(for: $0, on: now, completions: completions)
        })
        rescheduleTask?.cancel()
        rescheduleTask = Task { await apply(reminders, nudge: nudge, settledRoutineIDs: settledRoutineIDs) }
    }

    func snooze(_ routine: Routine, now: Date = .now) {
        let reminder = ReminderPlan.snooze(for: routine, now: now)
        Task { await add(reminder, categoryID: Self.routineCategoryID) }
    }

    private func apply(_ reminders: [PlannedReminder], nudge: PlannedReminder?, settledRoutineIDs: Set<UUID>) async {
        guard await isAuthorized() else { return }

        let pending = await center.pendingNotificationRequests().map(\.identifier)
        guard !Task.isCancelled else { return }
        let settledSnoozes = settledRoutineIDs.map { "\(ReminderPlan.snoozePrefix)\($0.uuidString)" }
        let owned = pending.filter {
            $0.hasPrefix(ReminderPlan.routinePrefix) || $0.hasPrefix(ReminderPlan.nudgePrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: owned + settledSnoozes)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.hasPrefix(ReminderPlan.nudgePrefix) && $0 != nudge?.id
        })
        guard !Task.isCancelled else { return }

        if let nudge { await add(nudge, categoryID: Self.nudgeCategoryID) }
        for reminder in reminders {
            await add(reminder, categoryID: Self.routineCategoryID)
        }
    }

    private func add(_ reminder: PlannedReminder, categoryID: String) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["routineID": reminder.routineID.uuidString]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.fireAt
        )
        let request = UNNotificationRequest(
            identifier: reminder.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("Could not schedule reminder: \(String(describing: error), privacy: .public)")
        }
    }

    private func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Routine reminders still show while the app is open. Step check-ins do not: the step is already on screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == Self.nudgeCategoryID ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let routineID = (response.notification.request.content.userInfo["routineID"] as? String)
            .flatMap(UUID.init(uuidString:))
        await MainActor.run {
            Self.handle(action: action, category: category, routineID: routineID)
        }
    }

    @MainActor
    private static func handle(action: String, category: String, routineID: UUID?) {
        let store = RoutineStore.shared
        let router = NextCueRouter.shared
        switch action {
        case startActionID:
            if store.activeRun == nil, let routineID { store.startRun(routineID: routineID) }
            router.presentRun()
        case snoozeActionID:
            guard let routine = store.routines.first(where: { $0.id == routineID }) else { return }
            shared.snooze(routine)
        case doneActionID:
            store.completeCurrentStep()
        case pauseActionID:
            store.pauseRun()
        case UNNotificationDefaultActionIdentifier:
            if category == nudgeCategoryID, store.activeRun != nil {
                router.presentRun()
            } else {
                router.showToday()
            }
        default:
            break
        }
    }
}
