import Foundation

/// Persists rating-ask eligibility. The ask itself is the system
/// `requestReview()` with no question in front of it (App Review 5.6.1).
@MainActor
enum ReviewPromptTracker {
    /// What the user did about a review. Only opening the review page ends the
    /// passive asks: someone who sent feedback can still rate.
    enum Outcome: String {
        case openedWriteReview
        /// Sent feedback by mail. Never stops the asks.
        case submittedFeedback
    }

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount = "nextcue.reviewPrompt.launchCount"
        static let lastShownDate = "nextcue.reviewPrompt.lastShownDate"
        static let outcome = "nextcue.reviewPrompt.outcome"
        static let pendingPositiveMoment = "nextcue.reviewPrompt.pendingPositiveMoment"
        /// Written by the old in-app rating card. Cleared on launch.
        static let legacyHandled = "nextcue.reviewPromptHandled"
    }

    /// Ask early. The only tenure gate is "not the first session": a second cold start.
    static let minimumLaunchCount = 2
    /// Days between our calls. Apple shows the prompt at most three times a
    /// year per device and decides each time, so this paces our asks.
    static let cooldownDays = 30

    /// UI tests and screenshot captures never count launches or ask.
    static var skipsAutomation: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains { $0 == "-ResetUITestData" || $0 == "-SeedScreenshotData" || $0 == "-PaywallSnapshot" || $0 == "-FASTLANE_SNAPSHOT" }
    }

    // MARK: - State

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: Key.launchCount), 0) }
        set { defaults.set(newValue, forKey: Key.launchCount) }
    }

    static var lastShownDate: Date? {
        get { (defaults.object(forKey: Key.lastShownDate) as? TimeInterval).map(Date.init(timeIntervalSince1970:)) }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: Key.lastShownDate)
            } else {
                defaults.removeObject(forKey: Key.lastShownDate)
            }
        }
    }

    static var outcome: Outcome? {
        get { defaults.string(forKey: Key.outcome).flatMap(Outcome.init(rawValue:)) }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: Key.outcome)
            } else {
                defaults.removeObject(forKey: Key.outcome)
            }
        }
    }

    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: Key.pendingPositiveMoment) }
        set { defaults.set(newValue, forKey: Key.pendingPositiveMoment) }
    }

    // MARK: - Recording

    static func recordAppLaunch() {
        defaults.removeObject(forKey: Key.legacyHandled)
        guard !skipsAutomation else { return }
        appLaunchCount += 1
    }

    static func recordPositiveMoment() {
        guard !skipsAutomation else { return }
        hasPendingPositiveMoment = true
    }

    // MARK: - Eligibility

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome != .openedWriteReview else { return false }
        guard let last = lastShownDate else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(cooldownDays) * 86_400
    }

    static func canRequestReview(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard !skipsAutomation, hasCompletedSetup, passivePromptAllowed(now: now) else { return false }
        return appLaunchCount >= minimumLaunchCount
    }

    static func shouldRequestAfterPositiveMoment(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    // MARK: - Outcomes

    static func markShown(now: Date = .now) {
        lastShownDate = now
        hasPendingPositiveMoment = false
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    /// Never overwrites `.openedWriteReview`: feedback sent after the review
    /// page must not reopen the asks that page ended.
    static func markFeedbackSubmitted() {
        if outcome != .openedWriteReview {
            outcome = .submittedFeedback
        }
    }
}
