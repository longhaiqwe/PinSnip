import CoreGraphics
import XCTest
@testable import PinSnipCore

final class WindowSelectionStateTests: XCTestCase {
    private let candidates = [
        WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
        WindowCandidate(id: 2, frame: CGRect(x: 20, y: 20, width: 100, height: 100))
    ]

    func testHoverSelectsWindowUnderPointer() {
        var state = WindowSelectionState(candidates: candidates)

        state.hover(at: CGPoint(x: 30, y: 30))

        XCTAssertEqual(state.rect, CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    func testClickLocksHoveredWindow() {
        var state = WindowSelectionState(candidates: candidates)
        let point = CGPoint(x: 30, y: 30)
        state.hover(at: point)
        state.begin(at: point)

        XCTAssertTrue(state.end(minimumDimension: 3))
        XCTAssertEqual(state.rect, CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    func testDragOverridesAutomaticWindowSelection() {
        var state = WindowSelectionState(candidates: candidates)
        state.begin(at: CGPoint(x: 30, y: 30))

        state.drag(to: CGPoint(x: 180, y: 120), inside: CGRect(x: 0, y: 0, width: 300, height: 200))

        XCTAssertTrue(state.end(minimumDimension: 3))
        XCTAssertEqual(state.rect, CGRect(x: 30, y: 30, width: 150, height: 90))
    }

    func testSubthresholdPointerJitterStillLocksHoveredWindow() {
        var state = WindowSelectionState(candidates: candidates)
        let point = CGPoint(x: 30, y: 30)
        state.hover(at: point)
        state.begin(at: point)

        state.drag(
            to: CGPoint(x: 31, y: 31),
            inside: CGRect(x: 0, y: 0, width: 300, height: 200)
        )

        XCTAssertTrue(state.end(minimumDimension: 3))
        XCTAssertEqual(state.rect, CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    func testHoverOutsideWindowsClearsAutomaticSelection() {
        var state = WindowSelectionState(candidates: candidates)
        state.hover(at: CGPoint(x: 30, y: 30))

        state.hover(at: CGPoint(x: 600, y: 600))

        XCTAssertEqual(state.rect, .zero)
    }

    func testDragAppliesFixedAspectConstraint() {
        var state = WindowSelectionState(candidates: [])
        state.begin(at: CGPoint(x: 10, y: 10))

        state.drag(
            to: CGPoint(x: 70, y: 30),
            inside: CGRect(x: 0, y: 0, width: 100, height: 100),
            constraint: SelectionConstraint(aspectRatio: 4.0 / 3.0)
        )

        XCTAssertEqual(state.rect, CGRect(x: 10, y: 10, width: 60, height: 45))
    }

    func testInitialRectRestoresLastCaptureRegion() {
        let expected = CGRect(x: 20, y: 30, width: 160, height: 90)

        let state = WindowSelectionState(candidates: [], initialRect: expected)

        XCTAssertEqual(state.rect, expected)
    }
}
