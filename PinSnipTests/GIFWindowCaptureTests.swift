import AppKit
import CoreVideo
import XCTest
import PinSnipCore

final class GIFWindowCaptureTests: XCTestCase {
    func testCacheStoresIncompressiblePixelsAsAnOwnedLosslessCopy() throws {
        let source = try XCTUnwrap(NSMutableData(length: 1_048_576))
        let words = source.mutableBytes.assumingMemoryBound(to: UInt32.self)
        var seed: UInt32 = 42
        for index in 0..<(source.length / 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            words[index] = seed | 0xff00_0000
        }
        let original = Data(bytes: source.bytes, count: source.length)
        let stored = try GIFFrameCacheData(copying: source.bytes, count: source.length)
        XCTAssertFalse(stored.isCompressed)
        XCTAssertEqual(stored.data.length, source.length)
        memset(source.mutableBytes, 0, source.length)
        XCTAssertEqual(try GIFFrameCacheData.decode(stored.data, isCompressed: stored.isCompressed) as Data, original)
    }

    func testCacheStillCompressesRepetitivePixelsLosslessly() throws {
        let source = Data(repeating: 0x7f, count: 1_048_576)
        let stored = try source.withUnsafeBytes {
            try GIFFrameCacheData(copying: $0.baseAddress!, count: $0.count)
        }
        XCTAssertTrue(stored.isCompressed)
        XCTAssertLessThan(stored.data.length, source.count / 10)
        XCTAssertEqual(try GIFFrameCacheData.decode(stored.data, isCompressed: stored.isCompressed) as Data, source)
    }

    func testRecordingReadsMixedCacheEncodingsAtTheirOwnOffsets() async throws {
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        try output.queue.sync {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, 512, 512, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            for frame in 0..<3 {
                CVPixelBufferLockBaseAddress(pixels, [])
                let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt32.self)
                var seed: UInt32 = 42
                for index in 0..<(CVPixelBufferGetBytesPerRow(pixels) * 512 / 4) {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    base[index] = frame == 1 ? seed | 0xff00_0000 : (frame == 0 ? 0xffff_0000 : 0xff00_00ff)
                }
                CVPixelBufferUnlockBaseAddress(pixels, [])
                output.append(pixels, timestamp: 10 + Double(frame) * 0.04)
            }
        }
        let data = await output.encode(endTimestamp: 10.12, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        let animation = try XCTUnwrap(AnimatedImage(data: XCTUnwrap(data)))
        XCTAssertEqual(animation.frames.count, 3)
        for frame in animation.frames { XCTAssertEqual(frame.duration, 0.04, accuracy: 0.001) }
        for index in [0, 2] {
            let bitmap = NSBitmapImageRep(cgImage: animation.frames[index].image)
            let color = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, index == 0 ? 1 : 0, accuracy: 0.02)
            XCTAssertEqual(color.blueComponent, index == 2 ? 1 : 0, accuracy: 0.02)
        }
    }

    @MainActor
    func testRecordingPreservesRetinaPixelsForTypicalSelection() {
        let geometry = ScreenRecordingGeometry(
            screenSize: CGSize(width: 1_440, height: 900),
            selectionRect: CGRect(x: 100, y: 100, width: 1_000, height: 600),
            backingScale: 2,
            maximumPixelDimension: ScreenGIFRecorder.maximumPixelDimension
        )
        XCTAssertEqual(geometry.outputPixelSize, CGSize(width: 2_000, height: 1_200))
    }

    @MainActor
    func testLargeRecordingUsesHigherResolutionWithoutChangingAspectRatio() {
        let geometry = ScreenRecordingGeometry(
            screenSize: CGSize(width: 1_920, height: 1_200),
            selectionRect: CGRect(x: 0, y: 0, width: 1_920, height: 1_200),
            backingScale: 2,
            maximumPixelDimension: ScreenGIFRecorder.maximumPixelDimension
        )
        XCTAssertEqual(geometry.outputPixelSize, CGSize(width: 2_400, height: 1_500))
    }

    @MainActor
    func testSmallRecordingIsNotArtificiallyUpscaled() {
        let geometry = ScreenRecordingGeometry(
            screenSize: CGSize(width: 1_920, height: 1_200),
            selectionRect: CGRect(x: 100, y: 100, width: 400, height: 250),
            backingScale: 1,
            maximumPixelDimension: ScreenGIFRecorder.maximumPixelDimension
        )
        XCTAssertEqual(geometry.outputPixelSize, CGSize(width: 400, height: 250))
    }

    @MainActor
    func testFullSizeFrameCacheKeepsUpWithRecordingBudget() throws {
        let dimension = Int(ScreenGIFRecorder.maximumPixelDimension)
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        defer { output.discard() }
        try output.queue.sync {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, dimension, dimension, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt32.self)
            let count = CVPixelBufferGetBytesPerRow(pixels) * dimension / 4
            // High entropy exercises the worst case for compression and disk
            // size, without capturing any private screen content.
            var seed: UInt32 = 42
            for index in 0..<count {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                base[index] = seed | 0xff00_0000
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            let start = ProcessInfo.processInfo.systemUptime
            for index in 0..<25 {
                output.append(pixels, timestamp: 10 + Double(index) * 0.04)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("GIF full-size lossless cache: \(elapsed * 1_000 / 25) ms/frame")
            XCTAssertLessThan(elapsed, 1, "25 frames must fit within one second of recording time")
        }
    }

    func testRetinaRecordingPreservesSinglePixelDetailThroughGIFExport() async throws {
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        try output.queue.sync {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, 2_000, 1_200, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt32.self)
            let rowWords = CVPixelBufferGetBytesPerRow(pixels) / 4
            for y in 0..<1_200 {
                for x in 0..<2_000 {
                    base[y * rowWords + x] = x.isMultiple(of: 2) ? 0xff00_0000 : 0xffff_ffff
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            output.append(pixels, timestamp: 10)
            output.append(pixels, timestamp: 10.04)
        }
        let data = await output.encode(endTimestamp: 10.08, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        let animation = try XCTUnwrap(AnimatedImage(data: XCTUnwrap(data)))
        XCTAssertEqual(animation.pixelWidth, 2_000)
        XCTAssertEqual(animation.pixelHeight, 1_200)
        for frame in animation.frames {
            let bitmap = NSBitmapImageRep(cgImage: frame.image)
            for x in 1_300..<1_320 {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: 600)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(color.redComponent, x.isMultiple(of: 2) ? 0 : 1, accuracy: 0.01)
            }
        }
    }

    func testLosslessFrameCachePreservesColorsAndStaticTail() async throws {
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        try output.queue.sync {
            for index in 0..<2 {
                var buffer: CVPixelBuffer?
                XCTAssertEqual(CVPixelBufferCreate(
                    nil, 17, 11, kCVPixelFormatType_32BGRA, nil, &buffer
                ), kCVReturnSuccess)
                let pixels = try XCTUnwrap(buffer)
                CVPixelBufferLockBaseAddress(pixels, [])
                let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(pixels)
                for y in 0..<11 {
                    for x in 0..<17 {
                        let offset = y * stride + x * 4
                        base[offset] = index == 0 ? 0 : 255
                        base[offset + 1] = 0
                        base[offset + 2] = index == 0 ? 255 : 0
                        base[offset + 3] = 255
                    }
                }
                CVPixelBufferUnlockBaseAddress(pixels, [])
                output.append(pixels, timestamp: 10 + Double(index) * 0.04)
            }
        }
        let data = await output.encode(endTimestamp: 12, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        let animation = try XCTUnwrap(AnimatedImage(data: XCTUnwrap(data)))
        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(animation.pixelWidth, 17)
        XCTAssertEqual(animation.pixelHeight, 11)
        XCTAssertEqual(animation.frames[0].duration, 0.04, accuracy: 0.001)
        XCTAssertEqual(animation.frames[1].duration, 1.96, accuracy: 0.001)
        for (index, frame) in animation.frames.enumerated() {
            let bitmap = NSBitmapImageRep(cgImage: frame.image)
            let color = try XCTUnwrap(bitmap.colorAt(x: 8, y: 5)?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, index == 0 ? 1 : 0, accuracy: 0.02)
            XCTAssertEqual(color.blueComponent, index == 0 ? 0 : 1, accuracy: 0.02)
        }
    }

    func testStaticRecordingPreservesDurationAndDiscardsLateFrames() async throws {
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        try output.queue.sync {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 255, CVPixelBufferGetBytesPerRow(pixels) * 4)
            CVPixelBufferUnlockBaseAddress(pixels, [])
            output.append(pixels, timestamp: 10)
            output.append(pixels, timestamp: 13)
        }
        let data = await output.encode(endTimestamp: 12, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        let animation = try XCTUnwrap(AnimatedImage(data: XCTUnwrap(data)))
        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(animation.frames.reduce(0) { $0 + $1.duration }, 2, accuracy: 0.001)
        let repeated = await output.encode(endTimestamp: 12, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        XCTAssertNil(repeated)
    }

    func testCancelledRecordingIgnoresLateFrames() async throws {
        let output = try GIFRecordingStreamOutput(onStopRequested: {})
        output.discard()
        try output.queue.sync {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            output.append(try XCTUnwrap(buffer), timestamp: 10)
        }
        let hasFrames = await output.hasFrames()
        XCTAssertFalse(hasFrames)
        let data = await output.encode(endTimestamp: 12, fallbackDuration: 0.04, style: .original, borderSize: .automatic)
        XCTAssertNil(data)
    }

    @MainActor
    func testRecordingFrameRateSupportsSmoothMotion() {
        XCTAssertGreaterThanOrEqual(ScreenGIFRecorder.framesPerSecond, 25)
    }

    @MainActor
    func testMovingContentRecordsAtLeastTwentyFramesPerSecond() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Live capture requires existing screen recording permission")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let selection = CGRect(x: 100, y: 100, width: 600, height: 400)
        let panel = NSPanel(
            contentRect: selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        defer { panel.close() }
        let recorder = ScreenGIFRecorder()
        defer { recorder.cancel() }
        try await recorder.start(screen: screen, selectionRect: selection, onStopRequested: {})
        let start = ProcessInfo.processInfo.systemUptime
        for index in 0..<120 {
            panel.backgroundColor = NSColor(calibratedHue: CGFloat(index % 60) / 60, saturation: 1, brightness: 1, alpha: 1)
            try await Task.sleep(for: .seconds(1.0 / 60))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let output = await recorder.stop(style: .original)
        let data = try XCTUnwrap(output)
        let animation = try XCTUnwrap(AnimatedImage(data: data))
        let fps = Double(animation.frames.count) / elapsed
        print("GIF recording: \(animation.frames.count) frames in \(elapsed)s = \(fps) fps")
        XCTAssertGreaterThanOrEqual(fps, 20)
        XCTAssertEqual(animation.frames.reduce(0) { $0 + $1.duration }, elapsed, accuracy: 0.2)
    }

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
