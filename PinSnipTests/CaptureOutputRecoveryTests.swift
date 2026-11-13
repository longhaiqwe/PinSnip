import AppKit
import PinSnipCore
import XCTest

final class CaptureOutputRecoveryTests: XCTestCase {
    @MainActor
    func testFailedAndCancelledSaveKeepGIFBytesUntilARealSaveSucceeds() throws {
        _ = NSApplication.shared
        let data = try gifData()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("recovered.gif")
        var attempt = 0
        var finished = 0
        let controller = GIFOutputRecoveryController(data: data, result: .cancelled, saveHandler: { bytes in
            XCTAssertEqual(bytes, data)
            attempt += 1
            if attempt == 1 { return CaptureOutputService.write(bytes, to: directory) }
            if attempt == 2 { return .cancelled }
            return CaptureOutputService.write(bytes, to: target)
        })
        defer { controller.close() }
        controller.onFinish = { finished += 1 }
        controller.retrySave()
        XCTAssertEqual(controller.pendingData, data)
        XCTAssertFalse(controller.isWorking)
        controller.retrySave()
        XCTAssertEqual(controller.pendingData, data)
        XCTAssertEqual(finished, 0)
        controller.retrySave()
        XCTAssertNil(controller.pendingData)
        XCTAssertEqual(try Data(contentsOf: target), data)
        XCTAssertEqual(finished, 1)
    }

    @MainActor
    func testCopyRetryRejectsRepeatedActionsAndReleasesBytesOnlyOnSuccess() throws {
        _ = NSApplication.shared
        let data = try gifData()
        var callback: ((CaptureOutputResult) -> Void)?
        var attempts = 0
        let controller = GIFOutputRecoveryController(data: data, result: .failed(CocoaError(.fileWriteUnknown)),
            copyHandler: { bytes, completion in
                XCTAssertEqual(bytes, data)
                attempts += 1
                callback = completion
            })
        defer { controller.close() }
        controller.retryCopy()
        controller.retryCopy()
        controller.retrySave()
        controller.discard()
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(controller.isWorking)
        XCTAssertEqual(controller.pendingData, data)
        try XCTUnwrap(callback)(.failed(CocoaError(.fileWriteUnknown)))
        XCTAssertFalse(controller.isWorking)
        XCTAssertEqual(controller.pendingData, data)
        controller.retryCopy()
        XCTAssertEqual(attempts, 2)
        try XCTUnwrap(callback)(.succeeded)
        XCTAssertNil(controller.pendingData)
    }

    @MainActor
    func testExplicitDiscardReleasesTheRetainedGIFAndDoesNotRetry() throws {
        _ = NSApplication.shared
        var attempts = 0
        let controller = GIFOutputRecoveryController(data: try gifData(), result: .cancelled,
            copyHandler: { _, _ in attempts += 1 })
        controller.discard()
        controller.retryCopy()
        XCTAssertNil(controller.pendingData)
        XCTAssertEqual(attempts, 0)
    }

    func testSaveFeedbackNeverClaimsAnUnstoredShelfCopyExists() {
        for result in [CaptureOutputResult.succeeded, .cancelled, .failed(CocoaError(.fileWriteUnknown))] {
            XCTAssertNil(CaptureSaveFeedback.message(for: result, isOnShelf: false))
        }
        XCTAssertNil(CaptureSaveFeedback.message(for: .succeeded, isOnShelf: true))
        XCTAssertTrue(CaptureSaveFeedback.message(for: .cancelled, isOnShelf: true)?.contains("已保留在晾衣架") == true)
        XCTAssertTrue(CaptureSaveFeedback.message(for: .failed(CocoaError(.fileWriteUnknown)), isOnShelf: true)?.contains("导出失败") == true)
    }

    @MainActor
    func testReadFailureStopsScrollingWithThePartialImageAndExplicitReason() async throws {
        let image = try testImage()
        let capture = ScreenScrollingCapture(frameProvider: { throw CocoaError(.fileReadUnknown) })
        var reason: ScrollingCaptureStopReason?
        try capture.startCollecting(firstImage: image, mode: .manual, onProgress: { _, _ in },
                                    onStopRequested: { reason = $0 })
        let deadline = ContinuousClock.now + .seconds(2)
        while reason == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard case let .interrupted(message, count) = try XCTUnwrap(reason) else {
            return XCTFail("A frame read error must not masquerade as normal completion")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(count, 1)
        let partial = await capture.stop()
        XCTAssertEqual(partial?.width, image.width)
        XCTAssertEqual(partial?.height, image.height)
        XCTAssertTrue(reason?.interruptionMessage?.contains("后续内容尚未截取") == true)
        XCTAssertNil(ScrollingCaptureStopReason.userFinished.interruptionMessage)
    }

    @MainActor
    func testCancelledFrameReadDoesNotShowAnInterruptionError() async throws {
        var read = false
        let capture = ScreenScrollingCapture(frameProvider: {
            read = true
            throw CancellationError()
        })
        var reason: ScrollingCaptureStopReason?
        try capture.startCollecting(firstImage: try testImage(), mode: .manual, onProgress: { _, _ in },
                                    onStopRequested: { reason = $0 })
        let deadline = ContinuousClock.now + .seconds(2)
        while !read, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(read)
        _ = await capture.stop()
        XCTAssertNil(reason)
    }

    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 18, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        return try XCTUnwrap(context.makeImage())
    }

    private func gifData() throws -> Data {
        let image = try testImage()
        return try XCTUnwrap(AnimatedGIFEncoder.encode(frames: [
            .init(image: image, duration: 0.1),
            .init(image: image, duration: 0.1)
        ]))
    }
}
