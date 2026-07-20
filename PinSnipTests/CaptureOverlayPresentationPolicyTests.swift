import XCTest
@testable import PinSnipCore

final class CaptureOverlayPresentationPolicyTests: XCTestCase {
    func testOverlayRemainsVisibleWhenMenuBarAppIsInactive() {
        XCTAssertFalse(CaptureOverlayPresentationPolicy.hidesOnDeactivate)
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
