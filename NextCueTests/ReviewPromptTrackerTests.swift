import Foundation
import XCTest
@testable import NextCue

/// The rating-ask rules from the fleet policy: ask from the second launch,
/// wait out a 30-day cooldown, stop only when the user opened the review page,
/// and never let feedback stop or restart the asks.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    /// Snapshots and restores the tracker's persisted state so the suite
    /// doesn't leave a simulator install mid-ask.
    private func withCleanTracker(_ body: () -> Void) {
        let launches = ReviewPromptTracker.appLaunchCount
        let lastShown = ReviewPromptTracker.lastShownDate
        let outcome = ReviewPromptTracker.outcome
        let pending = ReviewPromptTracker.hasPendingPositiveMoment
        defer {
            ReviewPromptTracker.appLaunchCount = launches
            ReviewPromptTracker.lastShownDate = lastShown
            ReviewPromptTracker.outcome = outcome
            ReviewPromptTracker.hasPendingPositiveMoment = pending
        }
        ReviewPromptTracker.outcome = nil
        ReviewPromptTracker.lastShownDate = nil
        ReviewPromptTracker.hasPendingPositiveMoment = false
        body()
    }

    func testAsksFromTheSecondSession() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 2
            XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    func testNeverAsksInTheFirstSession() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 1
            XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    func testStillRequiresARoutine() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: false))
        }
    }

    func testOpeningTheReviewPageEndsTheAsks() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            ReviewPromptTracker.markOpenedWriteReview()
            ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-365 * 86_400)
            XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    func testWaitsOutTheCooldown() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-10 * 86_400)
            XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
            ReviewPromptTracker.lastShownDate = Date.now.addingTimeInterval(-31 * 86_400)
            XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    func testFeedbackNeverEndsTheAsks() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            ReviewPromptTracker.markFeedbackSubmitted()
            XCTAssertEqual(ReviewPromptTracker.outcome, .submittedFeedback)
            XCTAssertNil(ReviewPromptTracker.lastShownDate, "feedback must not start a cooldown")
            XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    func testFeedbackAfterTheReviewPageKeepsTheAsksEnded() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            ReviewPromptTracker.markOpenedWriteReview()
            ReviewPromptTracker.markFeedbackSubmitted()
            XCTAssertEqual(ReviewPromptTracker.outcome, .openedWriteReview)
            XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedSetup: true))
        }
    }

    /// A moment whose ask finds something presented must survive that skip so
    /// the next finished routine can still ask.
    func testBlockedAskKeepsTheMomentPending() {
        withCleanTracker {
            ReviewPromptTracker.appLaunchCount = 9
            ReviewPromptTracker.recordPositiveMoment()
            XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
            XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
            ReviewPromptTracker.markShown()
            XCTAssertFalse(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
        }
    }
}
