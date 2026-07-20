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
}
