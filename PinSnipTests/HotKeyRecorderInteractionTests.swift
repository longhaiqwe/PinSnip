import AppKit
import Carbon
import XCTest
import PinSnipCore

final class HotKeyRecorderInteractionTests: XCTestCase {
    @MainActor
    func testReturnDoesNotSaveWhileRecordingAndEscapeOnlyCancelsRecording() throws {
        _ = NSApplication.shared
        var applyCount = 0
        var recordingChanges: [Bool] = []
        let controller = HotKeySettingsWindowController(settings: .standard,
            recordingStateChanged: { recordingChanges.append($0) },
            applyHandler: { _ in applyCount += 1; return true })
        let window = try XCTUnwrap(controller.window)
        let recorder = try XCTUnwrap(descendants(of: window.contentView!).compactMap {
            $0 as? HotKeyRecorderControl
        }.first)
        defer { controller.close() }

        recorder.performClick(nil)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(window.performKeyEquivalent(with: key(kVK_Return, characters: "\r")))
        XCTAssertTrue(recorder.isRecording, "Bare Return is invalid, and must not activate Save")
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(recorder.shortcut, HotKeySettings.standard.capture)

        XCTAssertTrue(window.performKeyEquivalent(with: key(kVK_Escape, characters: "\u{1b}")))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(recordingChanges, [true, false])
    }

    @MainActor
    func testCommandReturnRecordsShortcutInsteadOfSubmittingTheWindow() throws {
        _ = NSApplication.shared
        var applyCount = 0
        let controller = HotKeySettingsWindowController(settings: .standard,
            applyHandler: { _ in applyCount += 1; return true })
        let window = try XCTUnwrap(controller.window)
        let recorder = try XCTUnwrap(descendants(of: window.contentView!).compactMap {
            $0 as? HotKeyRecorderControl
        }.first)
        defer { controller.close() }

        recorder.performClick(nil)
        XCTAssertTrue(window.performKeyEquivalent(with: key(kVK_Return, characters: "\r", flags: .command)))
        XCTAssertEqual(recorder.shortcut, HotKeyShortcut(keyCode: UInt16(kVK_Return), modifiers: .command))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(applyCount, 0)
    }

    @MainActor
    func testLosingWindowFocusEndsRecordingAndReleasesSuspension() throws {
        _ = NSApplication.shared
        var recordingChanges: [Bool] = []
        let controller = HotKeySettingsWindowController(settings: .standard,
            recordingStateChanged: { recordingChanges.append($0) }, applyHandler: { _ in true })
        let window = try XCTUnwrap(controller.window)
        let recorders = descendants(of: window.contentView!).compactMap { $0 as? HotKeyRecorderControl }
        defer { controller.close() }

        recorders[0].performClick(nil)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        XCTAssertFalse(recorders.contains { $0.isRecording })
        XCTAssertEqual(recordingChanges, [true, false])

        recorders[1].performClick(nil)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        XCTAssertFalse(recorders.contains { $0.isRecording })
        XCTAssertEqual(recordingChanges, [true, false, true, false])
    }

    @MainActor
    func testDuplicateShortcutNamesBothActionsAndFocusesTheConflictingControl() throws {
        _ = NSApplication.shared
        var applyCount = 0
        let controller = HotKeySettingsWindowController(settings: .standard,
            applyHandler: { _ in applyCount += 1; return true })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let recorders = views.compactMap { $0 as? HotKeyRecorderControl }
        recorders[1].shortcut = recorders[0].shortcut
        try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" }).performClick(nil)

        XCTAssertEqual(applyCount, 0)
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("截图与录制动图都使用 F1")
        })
        XCTAssertTrue(window.firstResponder === recorders[1])
        XCTAssertEqual(recorders[2].shortcut, HotKeySettings.standard.paste)
    }

    @MainActor
    func testRegistrationFailureIdentifiesActionsAndPreservesEditedValues() throws {
        _ = NSApplication.shared
        let controller = HotKeySettingsWindowController(settings: .standard,
            registrationFailures: { [.recording, .paste] }, applyHandler: { _ in false })
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let recorders = views.compactMap { $0 as? HotKeyRecorderControl }
        try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" }).performClick(nil)

        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("录制动图（F3）、贴图（F4）注册失败")
        })
        XCTAssertTrue(window.firstResponder === recorders[1])
        XCTAssertEqual(recorders.map(\.shortcut), [HotKeySettings.standard.capture,
            HotKeySettings.standard.recording, HotKeySettings.standard.paste])
    }

    @MainActor
    func testReopeningHotKeySettingsPreservesTheWindowPosition() throws {
        _ = NSApplication.shared
        let first = HotKeySettingsWindowController(settings: .standard, applyHandler: { _ in true })
        let window = try XCTUnwrap(first.window)
        window.setFrameOrigin(NSPoint(x: 137, y: 181))
        first.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        let expected = window.frame
        first.close()
        let second = HotKeySettingsWindowController(settings: .standard, applyHandler: { _ in true })
        defer { second.close() }
        XCTAssertEqual(second.window?.frame, expected)
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func key(_ code: Int, characters: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: UInt16(code))!
    }
}
