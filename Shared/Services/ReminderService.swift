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
    nonisolated static let categoryID = "NEXTCUE_ROUTINE"
    nonisolated static let startActionID = "NEXTCUE_START"
    private static let requestPrefix = "nextcue.routine."

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "NextCue", category: "Reminders")
    private var rescheduleTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        let start = UNNotificationAction(
            identifier: Self.startActionID,
            title: "Start routine",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [start], intentIdentifiers: [])
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
        rescheduleTask?.cancel()
        rescheduleTask = Task { await apply(reminders) }
    }

    private func apply(_ reminders: [PlannedReminder]) async {
        let status = await center.notificationSettings().authorizationStatus
        let isAuthorized: Bool
        switch status {
        case .authorized, .provisional:
            isAuthorized = true
        #if os(iOS)
        case .ephemeral:
            isAuthorized = true
        #endif
        default:
            isAuthorized = false
        }
        guard isAuthorized else { return }

        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        let owned = pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: owned)
        guard !Task.isCancelled else { return }

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
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
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.startActionID,
              let rawID = response.notification.request.content.userInfo["routineID"] as? String,
              let routineID = UUID(uuidString: rawID) else { return }
        _ = await MainActor.run {
            RoutineStore.shared.startRun(routineID: routineID)
        }
    }
}
