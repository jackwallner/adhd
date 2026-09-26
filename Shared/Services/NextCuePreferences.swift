import Combine
import Foundation

/// Run preferences, shared by the app UI and the services that act on them.
enum NextCuePreferences {
    static let stepNudgesKey = "nextcue.stepNudges"
    static let stepTimerKey = "nextcue.stepTimer"
    static let keepAwakeKey = "nextcue.keepAwake"

    static var stepNudges: Bool { value(stepNudgesKey) }
    static var stepTimer: Bool { value(stepTimerKey) }
    static var keepAwake: Bool { value(keepAwakeKey) }

    private static func value(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// Screen requests that come from outside the view tree: notifications, Live Activities, and Shortcuts.
@MainActor
final class NextCueRouter: ObservableObject {
    static let shared = NextCueRouter()

    @Published var showRun = false
    /// Bumps when something outside the app asks for the Today tab.
    @Published private(set) var todayRequest = 0

    private init() {}

    func presentRun() {
        todayRequest += 1
        showRun = true
    }

    func showToday() {
        todayRequest += 1
    }
}
