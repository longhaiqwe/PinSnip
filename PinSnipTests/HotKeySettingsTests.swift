import Foundation
import XCTest
@testable import PinSnipCore

final class HotKeySettingsTests: XCTestCase {
    func testStandardBindingsUseF1ForCaptureF3ForRecordingAndF4ForPaste() {
        XCTAssertEqual(HotKeySettings.standard.capture, HotKeyShortcut(keyCode: 122))
        XCTAssertEqual(HotKeySettings.standard.recording, HotKeyShortcut(keyCode: 99))
        XCTAssertEqual(HotKeySettings.standard.paste, HotKeyShortcut(keyCode: 118))
    }

    func testRejectsDuplicateOrUnsafeBareKeyBindings() {
        let bareLetter = HotKeyShortcut(keyCode: 0)
        let shiftLetter = HotKeyShortcut(keyCode: 0, modifiers: [.shift])
        let commandLetter = HotKeyShortcut(keyCode: 0, modifiers: [.command])
        let duplicate = HotKeySettings(
            capture: commandLetter,
            recording: commandLetter,
            paste: HotKeyShortcut(keyCode: 35, modifiers: [.control, .option])
        )

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
            recording: HotKeyShortcut(keyCode: 15, modifiers: [.command, .option]),
            paste: HotKeyShortcut(keyCode: 35, modifiers: [.control, .option])
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testLegacySettingsKeepCustomCaptureWhileMovingPasteFromF3ToF4() throws {
        let suiteName = "PinSnipTests.HotKeySettings.Legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "legacy"
        let store = HotKeySettingsStore(defaults: defaults, key: key)
        let customCapture = HotKeyShortcut(keyCode: 49, modifiers: [.command, .shift])
        let legacy = LegacyHotKeySettings(
            capture: customCapture,
            paste: HotKeyShortcut(keyCode: 99)
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: key)

        XCTAssertEqual(
            store.load(),
            HotKeySettings(
                capture: customCapture,
                recording: HotKeyShortcut(keyCode: 99),
                paste: HotKeyShortcut(keyCode: 118)
            )
        )
    }
}

private struct LegacyHotKeySettings: Encodable {
    let capture: HotKeyShortcut
    let paste: HotKeyShortcut
}
