import CoreGraphics
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

    func testWindowCapturePreservesTransparencyAndExcludesShadow() {
        let configuration = WindowCaptureConfiguration(
            pointSize: CGSize(width: 320, height: 180),
            pixelScale: 2
        )

        XCTAssertEqual(configuration.pixelWidth, 640)
        XCTAssertEqual(configuration.pixelHeight, 360)
        XCTAssertFalse(configuration.shouldBeOpaque)
        XCTAssertTrue(configuration.ignoresShadow)
        XCTAssertTrue(configuration.scalesToFit)
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
