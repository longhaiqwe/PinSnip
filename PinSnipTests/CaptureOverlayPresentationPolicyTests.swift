import XCTest
@testable import PinSnipCore

final class CaptureOverlayPresentationPolicyTests: XCTestCase {
    func testStaticCaptureUsesOneScreenshotAttempt() {
        XCTAssertEqual(CapturePerformancePolicy.maximumScreenshotAttempts, 1)
    }

    func testConfiguredRectangleCaptureIsPreferredWhenAvailable() {
        XCTAssertEqual(
            CapturePerformancePolicy.captureRoute(
                supportsConfiguredRectangleCapture: true
            ),
            .configuredRectangle
        )
        XCTAssertEqual(
            CapturePerformancePolicy.captureRoute(
                supportsConfiguredRectangleCapture: false
            ),
            .filteredDisplay
        )
    }

    func testStaticScreenshotDoesNotCaptureCursor() {
        XCTAssertFalse(CaptureCursorPolicy.staticScreenshotShowsCursor)
    }

    func testOverlayRemainsVisibleWhenMenuBarAppIsInactive() {
        XCTAssertFalse(CaptureOverlayPresentationPolicy.hidesOnDeactivate)
    }

    func testOverlayPresentationPreservesFrontmostApplication() {
        XCTAssertTrue(CaptureOverlayPresentationPolicy.preservesFrontmostApplication)
    }

    func testOverlayAppearsWithoutWindowAnimation() {
        XCTAssertFalse(CaptureOverlayPresentationPolicy.animatesPresentation)
    }

    func testDimmingStartsOnlyAfterSelectionExists() {
        XCTAssertEqual(
            CaptureOverlayPresentationPolicy.dimmingOpacity(hasSelection: false),
            0
        )
        XCTAssertEqual(
            CaptureOverlayPresentationPolicy.dimmingOpacity(hasSelection: true),
            0.38
        )
    }
}
