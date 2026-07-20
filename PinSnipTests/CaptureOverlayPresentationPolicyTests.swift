import XCTest
@testable import PinSnipCore

final class CaptureOverlayPresentationPolicyTests: XCTestCase {
    func testOverlayRemainsVisibleWhenMenuBarAppIsInactive() {
        XCTAssertFalse(CaptureOverlayPresentationPolicy.hidesOnDeactivate)
    }
}
