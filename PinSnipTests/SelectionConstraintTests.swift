import CoreGraphics
import XCTest
@testable import PinSnipCore

final class SelectionConstraintTests: XCTestCase {
    func testSquareConstraintPreservesDragDirection() {
        XCTAssertEqual(
            SelectionConstraint(aspectRatio: 1).rect(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 60, y: 40),
                inside: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            CGRect(x: 10, y: 10, width: 50, height: 50)
        )
    }

    func testFourThreeConstraintUsesHorizontalDragAsWidth() {
        XCTAssertEqual(
            SelectionConstraint(aspectRatio: 4.0 / 3.0).rect(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 70, y: 30),
                inside: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            CGRect(x: 10, y: 10, width: 60, height: 45)
        )
    }

    func testSixteenNineConstraintUsesHorizontalDragAsWidth() {
        XCTAssertEqual(
            SelectionConstraint(aspectRatio: 16.0 / 9.0).rect(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 90, y: 30),
                inside: CGRect(x: 0, y: 0, width: 120, height: 100)
            ),
            CGRect(x: 10, y: 10, width: 80, height: 45)
        )
    }

    func testConstraintPreservesReverseDragDirection() {
        XCTAssertEqual(
            SelectionConstraint(aspectRatio: 4.0 / 3.0).rect(
                from: CGPoint(x: 80, y: 80),
                to: CGPoint(x: 20, y: 50),
                inside: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            CGRect(x: 20, y: 35, width: 60, height: 45)
        )
    }

    func testConstraintShrinksBothDimensionsAtBoundsToKeepRatio() {
        XCTAssertEqual(
            SelectionConstraint(aspectRatio: 1).rect(
                from: CGPoint(x: 90, y: 50),
                to: CGPoint(x: 140, y: 70),
                inside: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            CGRect(x: 90, y: 50, width: 10, height: 10)
        )
    }
}
