import CoreGraphics
import XCTest
@testable import PinSnipCore

final class SelectionAdjustmentTests: XCTestCase {
    private let rect = CGRect(x: 20, y: 30, width: 100, height: 80)

    func testHitTestingFindsAllEightResizeHandlesButNotTheInterior() {
        let expected: [(CGPoint, SelectionResizeHandle)] = [
            (CGPoint(x: 20, y: 110), .northWest),
            (CGPoint(x: 70, y: 110), .north),
            (CGPoint(x: 120, y: 110), .northEast),
            (CGPoint(x: 120, y: 70), .east),
            (CGPoint(x: 120, y: 30), .southEast),
            (CGPoint(x: 70, y: 30), .south),
            (CGPoint(x: 20, y: 30), .southWest),
            (CGPoint(x: 20, y: 70), .west)
        ]

        for (point, handle) in expected {
            XCTAssertEqual(
                SelectionAdjustment.handle(at: point, in: rect, hitRadius: 7),
                handle
            )
        }
        XCTAssertNil(
            SelectionAdjustment.handle(
                at: CGPoint(x: rect.midX, y: rect.midY),
                in: rect,
                hitRadius: 7
            )
        )
    }

    func testDraggingCornerResizesFromTheOppositeCorner() {
        let resized = SelectionAdjustment.resize(
            rect,
            using: .northEast,
            to: CGPoint(x: 160, y: 150),
            inside: CGRect(x: 0, y: 0, width: 300, height: 200),
            minimumDimension: 3
        )

        XCTAssertEqual(resized, CGRect(x: 20, y: 30, width: 140, height: 120))
    }

    func testDraggingEdgeClampsToBoundsAndPreservesTheOtherAxis() {
        let resized = SelectionAdjustment.resize(
            rect,
            using: .west,
            to: CGPoint(x: -50, y: 150),
            inside: CGRect(x: 0, y: 0, width: 300, height: 200),
            minimumDimension: 3
        )

        XCTAssertEqual(resized, CGRect(x: 0, y: 30, width: 120, height: 80))
    }

    func testDraggingEdgeCannotCollapseTheSelection() {
        let resized = SelectionAdjustment.resize(
            rect,
            using: .east,
            to: CGPoint(x: 21, y: 70),
            inside: CGRect(x: 0, y: 0, width: 300, height: 200),
            minimumDimension: 3
        )

        XCTAssertEqual(resized, CGRect(x: 20, y: 30, width: 3, height: 80))
    }
}
