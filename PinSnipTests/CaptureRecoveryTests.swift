import AppKit
import XCTest
@testable import PinSnipCore

final class CaptureRecoveryTests: XCTestCase {
    private actor Counter {
        private var count = 0
        func increment() -> Int { count += 1; return count }
        func value() -> Int { count }
    }

    private final class PendingValue: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int, Never>?
        private var value: Int?

        func wait() async -> Int {
            await withCheckedContinuation { continuation in
                let value = lock.withLock { () -> Int? in
                    if let value = self.value { return value }
                    self.continuation = continuation
                    return nil
                }
                if let value { continuation.resume(returning: value) }
            }
        }

        func finish(_ value: Int) {
            let pending = lock.withLock {
                self.value = value
                let pending = continuation
                continuation = nil
                return pending
            }
            pending?.resume(returning: value)
        }
    }

    func testUnresponsivePrimaryReturnsFallbackWithoutWaitingForNativeCallback() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20))
        let pending = PendingValue()
        let completed = expectation(description: "Fallback returns while native capture is stuck")
        let request = Task {
            let value = try await recovery.capture(primary: { await pending.wait() }, fallback: { 2 })
            completed.fulfill()
            return value
        }
        await fulfillment(of: [completed], timeout: 0.5)
        pending.finish(1)
        let result = try await request.value
        XCTAssertEqual(result, 2)
    }

    func testLatePrimaryCanWinAfterFallbackHasStarted() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20), fallbackTimeout: .seconds(1))
        let primary = PendingValue()
        let fallback = PendingValue()
        let fallbackStarted = expectation(description: "fallback started")
        let completed = expectation(description: "late primary returned without waiting for fallback")
        let request = Task {
            let value = try await recovery.capture(primary: { await primary.wait() }, fallback: {
                fallbackStarted.fulfill()
                return await fallback.wait()
            })
            completed.fulfill()
            return value
        }
        await fulfillment(of: [fallbackStarted], timeout: 1)
        primary.finish(1)
        await fulfillment(of: [completed], timeout: 0.3)
        fallback.finish(2)
        let value = try await request.value
        XCTAssertEqual(value, 1)
    }

    func testFallbackFailureDoesNotDiscardPendingPrimary() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20), fallbackTimeout: .seconds(1))
        let primary = PendingValue()
        let fallbackStarted = expectation(description: "fallback failed")
        let request = Task {
            try await recovery.capture(primary: { await primary.wait() }, fallback: {
                fallbackStarted.fulfill()
                throw CaptureRecoveryError.busy
            })
        }
        await fulfillment(of: [fallbackStarted], timeout: 1)
        primary.finish(9)
        let value = try await request.value
        XCTAssertEqual(value, 9)
    }

    func testPrewarmLeavesFallbackAvailableForImmediateForegroundCapture() async throws {
        let recovery = CaptureRecovery<Int>()
        let pending = PendingValue()
        let started = expectation(description: "warm-up started")
        let warmup = Task {
            await recovery.prewarm(primary: {
                started.fulfill()
                return await pending.wait()
            })
        }
        await fulfillment(of: [started], timeout: 0.5)
        let value = try await recovery.capture(primary: {
            XCTFail("Do not enqueue another primary while warm-up is outstanding")
            return 3
        }, fallback: { 2 })
        XCTAssertEqual(value, 2, "Foreground capture must use fresh fallback pixels without waiting for warm-up")
        pending.finish(1)
        await warmup.value
        let next = try await recovery.capture(primary: { 4 }, fallback: { 5 })
        XCTAssertEqual(next, 4, "Warm-up must release the primary slot and never cache its pixels")
    }

    func testPrewarmSkipsAnAlreadyRunningCapture() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .seconds(2))
        let pending = PendingValue()
        let started = expectation(description: "foreground started")
        let request = Task {
            try await recovery.capture(primary: {
                started.fulfill()
                return await pending.wait()
            }, fallback: { 2 })
        }
        await fulfillment(of: [started], timeout: 1)
        await recovery.prewarm(primary: { XCTFail("Warm-up must yield to foreground capture"); return 9 })
        pending.finish(1)
        let value = try await request.value
        XCTAssertEqual(value, 1)
    }

    func testPermissionDenialAfterFallbackStartsStillStopsCapture() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20))
        let primary = PendingValue()
        let fallback = PendingValue()
        let started = expectation(description: "fallback started")
        let completed = expectation(description: "permission rejection returned")
        let request = Task {
            do {
                _ = try await recovery.capture(primary: {
                    _ = await primary.wait()
                    throw ScreenCaptureError.permissionDenied
                }, fallback: {
                    started.fulfill()
                    return await fallback.wait()
                }, shouldFallback: { !ScreenCaptureService.isPermissionError($0) && !($0 is CancellationError) })
                XCTFail("Permission failure must not wait for fallback")
            } catch { XCTAssertTrue(ScreenCaptureService.isPermissionError(error)) }
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        primary.finish(1)
        await fulfillment(of: [completed], timeout: 0.5)
        fallback.finish(2)
        await request.value
    }

    func testHealthyPrimaryDoesNotInvokeFallback() async throws {
        let recovery = CaptureRecovery<Int>()
        let fallbackCalls = Counter()
        let value = try await recovery.capture(primary: { 7 }, fallback: { await fallbackCalls.increment() })
        let calls = await fallbackCalls.value()
        XCTAssertEqual(value, 7)
        XCTAssertEqual(calls, 0)
    }

    func testFurtherCapturesUseFreshFallbackWhilePrimaryIsStillHung() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20))
        let pending = PendingValue()
        let primaryCalls = Counter()
        let fallbackCalls = Counter()
        defer { pending.finish(99) }
        let primary: @Sendable () async throws -> Int = {
            _ = await primaryCalls.increment()
            return await pending.wait()
        }
        let first = try await recovery.capture(primary: primary, fallback: { await fallbackCalls.increment() })
        let second = try await recovery.capture(primary: primary, fallback: { await fallbackCalls.increment() })
        let calls = await primaryCalls.value()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2, "A new capture must not reuse the old primary's pixels")
        XCTAssertEqual(calls, 1, "Never enqueue another primary while its callback is outstanding")
    }

    func testPrimaryFailureImmediatelyUsesFallback() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .seconds(30))
        let value = try await recovery.capture(primary: { throw CaptureRecoveryError.busy }, fallback: { 8 })
        XCTAssertEqual(value, 8)
    }

    func testPermissionDenialDoesNotStartAnotherCaptureBackend() async throws {
        let recovery = CaptureRecovery<Int>()
        let fallbackCalls = Counter()
        do {
            _ = try await recovery.capture(primary: { throw ScreenCaptureError.permissionDenied }, fallback: {
                await fallbackCalls.increment()
            }, shouldFallback: { !ScreenCaptureService.isPermissionError($0) })
            XCTFail("Permission denial must be preserved")
        } catch {
            XCTAssertTrue(ScreenCaptureService.isPermissionError(error))
        }
        let calls = await fallbackCalls.value()
        XCTAssertEqual(calls, 0)
    }

    func testHungFallbackTimesOutAndDoesNotAccumulateMoreWork() async throws {
        let recovery = CaptureRecovery<Int>(primaryTimeout: .milliseconds(20), fallbackTimeout: .milliseconds(20))
        let primary = PendingValue()
        let fallback = PendingValue()
        defer { primary.finish(1); fallback.finish(2) }
        do {
            _ = try await recovery.capture(primary: { await primary.wait() }, fallback: { await fallback.wait() })
            XCTFail("Both hung backends must produce a bounded failure")
        } catch {
            guard case CaptureRecoveryError.timedOut = error else { return XCTFail("Unexpected: \(error)") }
        }
        do {
            _ = try await recovery.capture(primary: { XCTFail("Primary is still pending"); return 3 }, fallback: {
                XCTFail("Fallback is still pending"); return 4
            })
            XCTFail("Outstanding fallback must not be duplicated")
        } catch {
            guard case CaptureRecoveryError.busy = error else { return XCTFail("Unexpected: \(error)") }
        }
    }

    func testCancellationDoesNotLaunchFallbackOrWaitForUncooperativePrimary() async throws {
        let recovery = CaptureRecovery<Int>()
        let pending = PendingValue()
        let started = expectation(description: "primary started")
        let completed = expectation(description: "caller canceled")
        let fallbackCalls = Counter()
        let request = Task {
            do {
                _ = try await recovery.capture(primary: {
                    started.fulfill()
                    return await pending.wait()
                }, fallback: { await fallbackCalls.increment() })
                XCTFail("Expected cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        await fulfillment(of: [completed], timeout: 0.5)
        pending.finish(1)
        await request.value
        let calls = await fallbackCalls.value()
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testLiveFallbackIncludesVisibleWindowWhenPrimaryNeverReturns() async throws {
        guard CGPreflightScreenCaptureAccess() else { throw XCTSkip("Screen recording permission unavailable") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let marker = NSWindow(contentRect: CGRect(x: screen.frame.midX - 100, y: screen.frame.midY - 60,
            width: 200, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        marker.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        marker.isOpaque = true
        marker.level = .floating
        marker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        marker.orderFrontRegardless()
        defer { marker.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))

        let pending = PendingValue()
        defer { pending.finish(1) }
        let recovery = CaptureRecovery<CGImage>(primaryTimeout: .milliseconds(20))
        let image = try await recovery.capture(primary: {
            _ = await pending.wait()
            throw CancellationError()
        }, fallback: { try await ScreenCaptureService.captureFallbackDisplay(displayID) })

        XCTAssertEqual(image.width, Int(screen.frame.width * screen.backingScaleFactor))
        XCTAssertEqual(image.height, Int(screen.frame.height * screen.backingScaleFactor))
        let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(rgba[0], 220, "Fallback must capture the test window, not just wallpaper")
        XCTAssertLessThan(rgba[1], 40)
        XCTAssertGreaterThan(rgba[2], 220)
    }
}
