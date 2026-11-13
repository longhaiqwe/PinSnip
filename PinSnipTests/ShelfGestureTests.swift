import AppKit
import XCTest

@MainActor
final class ShelfGestureTests: XCTestCase {
    func testDoubleClickPinsWithoutOverwritingClipboardAndSingleClickCopiesOnce() async throws {
        let view = ShelfGrabView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.copyDelay = 0.04
        var copied = 0
        var pinned = 0
        view.onClick = { copied += 1 }
        view.onDoubleClick = { pinned += 1 }

        view.mouseDown(with: try mouse(.leftMouseDown, clicks: 1))
        view.mouseUp(with: try mouse(.leftMouseUp, clicks: 1))
        view.mouseDown(with: try mouse(.leftMouseDown, clicks: 2))
        view.mouseUp(with: try mouse(.leftMouseUp, clicks: 2))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(pinned, 1)
        XCTAssertEqual(copied, 0)

        view.mouseDown(with: try mouse(.leftMouseDown, clicks: 1))
        view.mouseUp(with: try mouse(.leftMouseUp, clicks: 1))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(copied, 1)
    }

    func testAccessibilityActionsAndKeyboardReachCardOperations() throws {
        let view = ShelfGrabView(frame: .zero)
        var copied = 0
        var pinned = 0
        var removed = 0
        view.onClick = { copied += 1 }
        view.onDoubleClick = { pinned += 1 }
        view.onDiscard = { removed += 1 }
        XCTAssertTrue(view.acceptsFirstResponder)
        XCTAssertEqual(view.accessibilityRole(), .button)
        XCTAssertTrue(view.accessibilityPerformPress())
        let actions = try XCTUnwrap(view.accessibilityCustomActions())
        XCTAssertTrue(try XCTUnwrap(actions.first { $0.name == "贴在桌面" }?.handler)())
        XCTAssertTrue(try XCTUnwrap(actions.first { $0.name == "从晾衣架取下" }?.handler)())
        for (code, text) in [(UInt16(49), " "), (36, "\r"), (51, "\u{7f}")] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code))
            view.keyDown(with: event)
        }
        XCTAssertEqual(copied, 2)
        XCTAssertEqual(pinned, 2)
        XCTAssertEqual(removed, 2)
    }

    private func mouse(_ type: NSEvent.EventType, clicks: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
    }
}
