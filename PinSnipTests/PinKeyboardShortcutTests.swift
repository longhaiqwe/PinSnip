import XCTest
@testable import PinSnipCore

final class PinKeyboardShortcutTests: XCTestCase {
    func testEscapeClosesActivePin() {
        XCTAssertTrue(
            PinKeyboardShortcut.shouldClose(
                character: "\u{1B}",
                commandPressed: false
            )
        )
    }

    func testCommandWStillClosesActivePin() {
        XCTAssertTrue(
            PinKeyboardShortcut.shouldClose(
                character: "w",
                commandPressed: true
            )
        )
    }

    func testPlainWDoesNotCloseActivePin() {
        XCTAssertFalse(
            PinKeyboardShortcut.shouldClose(
                character: "w",
                commandPressed: false
            )
        )
    }
}
