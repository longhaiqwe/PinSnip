import CoreGraphics
import XCTest
@testable import PinSnipCore

final class WindowCandidateTests: XCTestCase {
    func testSmallestContainingWindowWins() {
        let candidates = [
            WindowCandidate(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
            WindowCandidate(id: 2, frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        ]

        XCTAssertEqual(WindowCandidate.best(at: CGPoint(x: 30, y: 30), in: candidates)?.id, 2)
    }

    func testReturnsNilWhenPointIsOutsideEveryWindow() {
        let candidates = [
            WindowCandidate(id: 1, frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        ]

        XCTAssertNil(WindowCandidate.best(at: CGPoint(x: 5, y: 5), in: candidates))
    }

    func testFrontmostWindowWinsOverSmallerCoveredWindow() {
        let candidates = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                zOrder: 0
            ),
            WindowCandidate(
                id: 2,
                frame: CGRect(x: 20, y: 20, width: 100, height: 100),
                zOrder: 1
            )
        ]

        XCTAssertEqual(WindowCandidate.best(at: CGPoint(x: 30, y: 30), in: candidates)?.id, 1)
    }
}
