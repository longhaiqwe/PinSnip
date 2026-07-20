import Foundation
import XCTest
@testable import PinSnipCore

final class HotKeySettingsTests: XCTestCase {
    func testStandardBindingsUseF1ForCaptureAndF3ForPaste() {
        XCTAssertEqual(HotKeySettings.standard.capture, HotKeyShortcut(keyCode: 122))
        XCTAssertEqual(HotKeySettings.standard.paste, HotKeyShortcut(keyCode: 99))
    }

    func testRejectsDuplicateOrUnsafeBareKeyBindings() {
        let bareLetter = HotKeyShortcut(keyCode: 0)
        let shiftLetter = HotKeyShortcut(keyCode: 0, modifiers: [.shift])
        let commandLetter = HotKeyShortcut(keyCode: 0, modifiers: [.command])
        let duplicate = HotKeySettings(capture: commandLetter, paste: commandLetter)

        XCTAssertFalse(bareLetter.isValid)
        XCTAssertFalse(shiftLetter.isValid)
        XCTAssertTrue(commandLetter.isValid)
        XCTAssertFalse(duplicate.isValid)
    }

    func testSettingsRoundTripThroughStore() throws {
        let suiteName = "PinSnipTests.HotKeySettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HotKeySettingsStore(defaults: defaults)
        let settings = HotKeySettings(
            capture: HotKeyShortcut(keyCode: 49, modifiers: [.command, .shift]),
            paste: HotKeyShortcut(keyCode: 35, modifiers: [.control, .option])
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }
}
