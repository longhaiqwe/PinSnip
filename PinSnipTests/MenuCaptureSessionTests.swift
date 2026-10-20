import AppKit
import XCTest

final class MenuCaptureSessionTests: XCTestCase {
    @MainActor
    private final class Menu: NSMenu {
        var cancellations = 0
        override func cancelTrackingWithoutAnimation() { cancellations += 1 }
    }

    @MainActor
    func testSnapshotCompletesBeforeClosingMenuAndDeliveryWaitsForDefaultLoop() throws {
        _ = NSApplication.shared
        let menu = Menu()
        let session = MenuCaptureSession(menus: [menu])
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        var delivered: CGImage?
        session.start(capture: {
            try await Task.sleep(for: .milliseconds(30))
            return image
        }) { result in delivered = try? result.get() }
        XCTAssertEqual(menu.cancellations, 0)
        pump(.eventTracking, until: { menu.cancellations > 0 })
        XCTAssertEqual(menu.cancellations, 1)
        XCTAssertNil(delivered, "Overlay cannot take focus inside the menu loop")
        pump(.default, until: { delivered != nil })
        XCTAssertTrue(delivered === image, "Export must use the snapshot made with the menu visible")
    }

    @MainActor
    func testTimeoutUnblocksTrackingWithoutWaitingForCapture() {
        _ = NSApplication.shared
        let menu = Menu()
        let session = MenuCaptureSession(menus: [menu])
        var timedOut = false
        session.start(timeout: .milliseconds(20), capture: {
            try await Task.sleep(for: .seconds(20))
            throw CancellationError()
        }) { result in
            if case .failure(let error) = result { timedOut = error is MenuCaptureSession.Failure }
        }
        pump(.eventTracking, until: { menu.cancellations > 0 })
        XCTAssertEqual(menu.cancellations, 1)
        pump(.default, until: { timedOut })
        XCTAssertTrue(timedOut)
    }

    @MainActor
    func testCancellationDoesNotCloseMenusOrPresentAnError() {
        _ = NSApplication.shared
        let menu = Menu()
        let session = MenuCaptureSession(menus: [menu])
        var completed = false
        session.start(timeout: .milliseconds(10), capture: {
            try await Task.sleep(for: .seconds(20))
            throw CancellationError()
        }) { _ in completed = true }
        session.cancel()
        let deadline = Date().addingTimeInterval(0.05)
        pump(.eventTracking, until: { Date() >= deadline })
        XCTAssertEqual(menu.cancellations, 0)
        XCTAssertFalse(completed)
    }

    @MainActor
    private func pump(_ mode: RunLoop.Mode, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.005))
        }
    }
}
