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

    func testApplicationWindowWinsOverNearlyIdenticalVisualRegion() {
        let applicationWindow = WindowCandidate(
            id: 21_872,
            frame: CGRect(x: 638, y: 284, width: 980, height: 712),
            zOrder: 36
        )
        let approximateVisualRegion = WindowCandidate(
            id: .max,
            frame: CGRect(x: 643, y: 288, width: 966, height: 699),
            kind: .visualRegion
        )

        let candidate = WindowCandidate.best(
            at: CGPoint(x: 900, y: 640),
            in: [applicationWindow, approximateVisualRegion]
        )

        XCTAssertEqual(candidate, applicationWindow)
    }

    func testStableCandidatesExcludeWindowThatMovedDuringScreenshotCapture() {
        let before = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 100, y: 80, width: 500, height: 360),
                zOrder: 0
            )
        ]
        let after = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 105, y: 83, width: 500, height: 360),
                zOrder: 0
            )
        ]

        XCTAssertTrue(
            WindowCandidate.stableCandidates(before: before, after: after).isEmpty
        )
    }

    func testStableCandidatesAllowSubpixelCoordinateNoise() {
        let before = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 100, y: 80, width: 500, height: 360),
                zOrder: 0
            )
        ]
        let after = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 100.25, y: 79.75, width: 500.25, height: 359.75),
                zOrder: 0
            )
        ]

        XCTAssertEqual(
            WindowCandidate.stableCandidates(before: before, after: after),
            after
        )
    }

    func testWindowUnderPointerRequiresRecaptureWhenItMoves() {
        let before = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 100, y: 80, width: 500, height: 360),
                zOrder: 0
            )
        ]
        let after = [
            WindowCandidate(
                id: 1,
                frame: CGRect(x: 105, y: 83, width: 500, height: 360),
                zOrder: 0
            )
        ]

        XCTAssertTrue(
            WindowCandidate.requiresRecapture(
                at: CGPoint(x: 300, y: 200),
                before: before,
                after: after
            )
        )
    }
}
