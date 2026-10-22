import XCTest
@testable import NextCue

final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 470...481))
        // The folded outer display.
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
    }

    func testRegularWidthTooNarrowForTwoPanesKeepsOneColumn() {
        // The unfolded display held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 470...481))
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 470))
    }

    func testZeroWidthFoldSplitsAtTheLine() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 475.5...475.5))
        XCTAssertEqual(split.primaryWidth, 475.5)
        XCTAssertEqual(split.secondaryX, 475.5)
        XCTAssertEqual(split.secondaryWidth, 475.5)
    }

    func testNoFoldSplitsEvenly() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil))
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldLeavingANarrowPaneFallsBackToEvenSplit() throws {
        let split = try XCTUnwrap(UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 300...310))
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
    }

    func testPanesAreAtLeastTheMinimumWidth() throws {
        for width in stride(from: CGFloat(720), through: 1400, by: 37) {
            let split = try XCTUnwrap(UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil))
            XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertEqual(split.secondaryX + split.secondaryWidth, width)
        }
    }
}
