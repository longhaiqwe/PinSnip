import AppKit
import PinSnipCore
import XCTest

final class MenuCaptureSessionTests: XCTestCase {
    /// Models a system callback that does not observe Swift task cancellation.
    private final class PendingCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?

        var hasStarted: Bool { lock.withLock { continuation != nil } }

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.withLock { self.continuation = continuation }
            }
        }

        func finish() {
            let pending = lock.withLock {
                let pending = continuation
                continuation = nil
                return pending
            }
            pending?.resume()
        }
    }

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
    func testTimedOutSystemRequestBlocksRetryUntilItsLateCallback() throws {
        _ = NSApplication.shared
        let menu = Menu()
        let session = MenuCaptureSession(menus: [menu])
        let pending = PendingCapture()
        defer { pending.finish() }
        var state = CaptureSessionState()
        let id = try XCTUnwrap(state.begin())
        var completions = 0
        var finished = false
        session.start(timeout: .milliseconds(100), capture: {
            await pending.wait()
            throw CancellationError()
        }, onCaptureFinished: {
            finished = true
            state.captureFinished(id)
        }) { _ in
            completions += 1
            state.end(id)
        }

        pump(.eventTracking, until: { pending.hasStarted })
        XCTAssertTrue(pending.hasStarted)
        pump(.eventTracking, until: { menu.cancellations > 0 })
        pump(.default, until: { completions > 0 })
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(finished)
        XCTAssertNil(state.begin())

        pending.finish()
        pump(.eventTracking, until: { finished })
        XCTAssertTrue(finished)
        XCTAssertEqual(completions, 1, "Late callbacks must not present another result")
        XCTAssertNotNil(state.begin())
    }

    @MainActor
    func testCanceledMenuSessionReleasesRequestEvenAfterSessionIsDestroyed() {
        _ = NSApplication.shared
        var session: MenuCaptureSession? = MenuCaptureSession(menus: [])
        let pending = PendingCapture()
        defer { pending.finish() }
        var finished = false
        var delivered = false
        session?.start(capture: {
            await pending.wait()
            throw CancellationError()
        }, onCaptureFinished: { finished = true }) { _ in delivered = true }
        pump(.eventTracking, until: { pending.hasStarted })
        XCTAssertTrue(pending.hasStarted)
        session?.cancel()
        session = nil
        XCTAssertFalse(finished)
        pending.finish()
        pump(.eventTracking, until: { finished })
        XCTAssertTrue(finished)
        XCTAssertFalse(delivered)
    }

    @MainActor
    func testFallbackCompletesMenuCaptureWhilePrimaryRemainsStuck() throws {
        _ = NSApplication.shared
        let menu = Menu()
        let session = MenuCaptureSession(menus: [menu])
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        var delivered: CGImage?
        let pending = PendingCapture()
        defer { pending.finish() }
        let recovery = CaptureRecovery<CGImage>(primaryTimeout: .milliseconds(20))
        session.start(timeout: .milliseconds(500), capture: {
            try await recovery.capture(primary: {
                await pending.wait()
                throw CancellationError()
            }, fallback: { image })
        }) { result in delivered = try? result.get() }
        pump(.eventTracking, until: { menu.cancellations > 0 })
        pump(.default, until: { delivered != nil })
        XCTAssertTrue(delivered === image)
    }

    @MainActor
    private func pump(_ mode: RunLoop.Mode, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.005))
        }
    }
}
