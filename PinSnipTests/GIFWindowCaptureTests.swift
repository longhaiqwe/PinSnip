import AppKit
import XCTest
import PinSnipCore

final class GIFWindowCaptureTests: XCTestCase {
    func testRecordingDoesNotExcludeItsEntireApplication() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("PinSnip/Capture/ScreenGIFRecorder.swift"), encoding: .utf8)
        // Guard the ScreenCaptureKit integration even on CI without capture permission.
        XCTAssertFalse(source.contains("excludingApplications:"), "Excluding PinSnip also removes the shelf and pins")
        XCTAssertTrue(source.contains("excludingWindows:"))
    }

    @MainActor
    func testRecordingIncludesWindowsFromItsOwnApplication() async throws {
        try await recordOwnWindow(excludeCover: false)
    }

    @MainActor
    func testRecordingExcludesOnlyTheSpecifiedControlWindow() async throws {
        try await recordOwnWindow(excludeCover: true)
    }

    @MainActor
    func testRecordingControlsExposeBothWindowIDsAndKeepThemStable() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let before = Set(NSApp.windows.filter(\.isVisible).map { CGWindowID($0.windowNumber) })
        let controller = GIFRecordingPanelController(
            screen: screen, selectionRect: CGRect(x: 40, y: 40, width: 100, height: 100)
        )
        defer { controller.finish() }
        controller.present()
        let IDs = controller.recordingWindowIDs
        let after = Set(NSApp.windows.filter(\.isVisible).map { CGWindowID($0.windowNumber) })
        XCTAssertEqual(IDs.count, 2, "Both the toolbar and recording border must be excluded")
        XCTAssertEqual(after.subtracting(before), IDs)
        controller.recordingDidStart()
        XCTAssertEqual(controller.recordingWindowIDs, IDs)
        controller.finish()
        XCTAssertTrue(NSApp.windows.filter { IDs.contains(CGWindowID($0.windowNumber)) }.allSatisfy { !$0.isVisible })
    }

    @MainActor
    private func recordOwnWindow(excludeCover: Bool) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Live capture requires existing screen recording permission")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let selection = CGRect(x: screen.frame.width / 2, y: screen.frame.height / 2, width: 100, height: 100)
        let panel = NSPanel(
            contentRect: selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.backgroundColor = .red
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        defer { panel.close() }
        let cover = NSPanel(contentRect: panel.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        cover.backgroundColor = .blue
        cover.isOpaque = true
        cover.hasShadow = false
        cover.level = .screenSaver
        cover.isReleasedWhenClosed = false
        if excludeCover { cover.orderFrontRegardless() }
        defer { cover.close() }
        try await Task.sleep(for: .milliseconds(200))

        let recorder = ScreenGIFRecorder()
        defer { recorder.cancel() }
        try await recorder.start(
            screen: screen, selectionRect: selection,
            excludingWindowIDs: excludeCover ? [CGWindowID(cover.windowNumber)] : [],
            onStopRequested: {}
        )
        let output = await recorder.stop(style: .original)
        let animation = try XCTUnwrap(AnimatedImage(data: XCTUnwrap(output)))
        let frame = try XCTUnwrap(animation.frames.first)
        let bitmap = NSBitmapImageRep(cgImage: frame.image)
        let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.85, "Shelf and pin windows must remain in recorded frames")
        XCTAssertLessThan(color.greenComponent, 0.15)
        XCTAssertLessThan(color.blueComponent, 0.15)
    }
}
