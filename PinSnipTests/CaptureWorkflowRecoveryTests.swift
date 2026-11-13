import AppKit
import PinSnipCore
import XCTest

final class CaptureWorkflowRecoveryTests: XCTestCase {
    @MainActor
    func testDeletingASelectedRectangleSupportsUndoAndRedo() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var result: CaptureResult?
        let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
            initialSelectionRect: CGRect(x: 20, y: 20, width: 560, height: 360), purpose: .stillImage,
            onResult: { result = $0 }, onCancel: {})
        window.contentView = overlay
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        overlay.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
        overlay.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 250, y: 220)))
        overlay.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 250, y: 220)))
        overlay.keyDown(with: try key(36, "\r"))
        let original = try XCTUnwrap(result?.annotations)
        XCTAssertEqual(original.count, 1)
        overlay.keyDown(with: try key(51, "\u{7f}"))
        overlay.keyDown(with: try key(36, "\r"))
        XCTAssertEqual(result?.annotations.count, 0)
        overlay.keyDown(with: try key(6, "z", modifiers: .command))
        overlay.keyDown(with: try key(36, "\r"))
        XCTAssertEqual(result?.annotations, original)
        overlay.keyDown(with: try key(6, "z", modifiers: [.command, .shift]))
        overlay.keyDown(with: try key(36, "\r"))
        XCTAssertEqual(result?.annotations.count, 0)
    }

    @MainActor
    func testExportRejectsDuplicateCompletionUntilPendingWorkFinishes() throws {
        _ = NSApplication.shared
        let coordinator = CaptureCoordinator(pinManager: PinWindowManager())
        var pending: CheckedContinuation<Void, Never>?
        var outputs: [String] = []

        XCTAssertTrue(coordinator.performCaptureExport {
            await withCheckedContinuation { pending = $0 }
            outputs.append("first")
        })
        XCTAssertTrue(coordinator.isExportingCapture)
        XCTAssertFalse(coordinator.performCaptureExport { outputs.append("duplicate") })
        pump { pending != nil }
        let continuation = try XCTUnwrap(pending)
        // Esc arriving from an already queued event must not release an export's slot.
        coordinator.cancelActiveCapture()
        XCTAssertTrue(coordinator.isExportingCapture)
        XCTAssertFalse(coordinator.performCaptureExport { outputs.append("overlapping") })
        continuation.resume()
        pump { !coordinator.isExportingCapture }
        XCTAssertFalse(coordinator.isExportingCapture)
        XCTAssertEqual(outputs, ["first"])

        XCTAssertTrue(coordinator.performCaptureExport { outputs.append("next") })
        pump { !coordinator.isExportingCapture }
        XCTAssertEqual(outputs, ["first", "next"])
    }

    @MainActor
    func testEnterWithoutASelectionKeepsEveryCaptureModeOpenAndAllowsRetry() throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let screenshot = try XCTUnwrap(context.makeImage())
        for purpose in [CaptureOverlayPurpose.stillImage, .animatedGIF, .scrollingCapture] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            var results: [CaptureResult] = []
            var cancelled = false
            let overlay = SelectionOverlayView(
                frame: CGRect(x: 0, y: 0, width: 600, height: 400), screenshot: screenshot,
                windowCandidates: [], initialPointer: .zero, initialSelectionRect: .zero,
                purpose: purpose, onResult: { results.append($0) }, onCancel: { cancelled = true }
            )
            window.contentView = overlay
            let enter = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
            ))
            overlay.keyDown(with: enter)
            XCTAssertTrue(results.isEmpty, "An empty selection cannot start \(purpose)")
            XCTAssertFalse(cancelled)

            let start = CGPoint(x: 60, y: 70)
            let end = CGPoint(x: 320, y: 250)
            func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: 1
                ))
            }
            overlay.mouseDown(with: try mouse(.leftMouseDown, start))
            overlay.mouseDragged(with: try mouse(.leftMouseDragged, end))
            overlay.mouseUp(with: try mouse(.leftMouseUp, end))
            overlay.keyDown(with: enter)
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.selectionRect, CGRect(x: 60, y: 70, width: 260, height: 180))
            XCTAssertFalse(cancelled)
        }
    }

    @MainActor
    private func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }
}
