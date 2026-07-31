import XCTest
@testable import PinSnipCore

final class CapturePanelKeyboardShortcutTests: XCTestCase {
    func testEscapeCancelsAnActiveCapturePanel() {
        XCTAssertEqual(
            CapturePanelKeyboardShortcut.action(keyCode: 53),
            .cancel
        )
    }

    func testOtherKeysRemainAvailableToTheFrontmostApplication() {
        XCTAssertNil(CapturePanelKeyboardShortcut.action(keyCode: 49))
    }
}
