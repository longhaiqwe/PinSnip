import CoreGraphics
import XCTest
@testable import PinSnipCore

final class SelectionRectTests: XCTestCase {
    func testDragNormalizesInEveryDirection() {
        let selection = SelectionRect(
            start: CGPoint(x: 80, y: 50),
            end: CGPoint(x: 20, y: 10)
        )

        XCTAssertEqual(selection.rect, CGRect(x: 20, y: 10, width: 60, height: 40))
    }

    func testClampedSelectionStaysInsideBounds() {
        let selection = SelectionRect(
            start: CGPoint(x: -5, y: 10),
            end: CGPoint(x: 120, y: 90)
        )

        XCTAssertEqual(
            selection.clamped(to: CGRect(x: 0, y: 0, width: 100, height: 80)).rect,
            CGRect(x: 0, y: 10, width: 100, height: 70)
        )
    }

    func testZeroSizedSelectionIsEmpty() {
        let selection = SelectionRect(start: CGPoint(x: 8, y: 8), end: CGPoint(x: 8, y: 8))

        XCTAssertTrue(selection.isEmpty)
    }
}
