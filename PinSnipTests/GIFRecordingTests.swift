import CoreGraphics
import XCTest
@testable import PinSnipCore

final class GIFRecordingTests: XCTestCase {
    func testMapsBottomLeftSelectionToTopLeftCaptureRegionAndCapsOutputSize() {
        let geometry = ScreenRecordingGeometry(
            screenSize: CGSize(width: 1_440, height: 900),
            selectionRect: CGRect(x: 100, y: 200, width: 800, height: 500),
            backingScale: 2,
            maximumPixelDimension: 1_200
        )

        XCTAssertEqual(geometry.sourceRect, CGRect(x: 100, y: 200, width: 800, height: 500))
        XCTAssertEqual(geometry.outputPixelSize, CGSize(width: 1_200, height: 750))
    }

    func testFrameTimelineUsesCaptureIntervalsAndFallbackForTheLastFrame() {
        let durations = GIFFrameTimeline.durations(
            for: [10, 10.11, 10.31],
            fallbackDuration: 0.1
        )

        XCTAssertEqual(durations[0], 0.11, accuracy: 0.001)
        XCTAssertEqual(durations[1], 0.20, accuracy: 0.001)
        XCTAssertEqual(durations[2], 0.10, accuracy: 0.001)
    }

    func testEncodesCapturedFramesAsAnAnimatedGIF() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]

        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames))
        let decoded = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertEqual(decoded.frames.count, 2)
        XCTAssertEqual(decoded.frames[0].duration, 0.08, accuracy: 0.011)
        XCTAssertEqual(decoded.frames[1].duration, 0.16, accuracy: 0.011)
        XCTAssertEqual(decoded.loopCount, 0)
    }

    func testGIFTimingDoesNotAccumulateRoundingErrorAcrossFrames() throws {
        let image = try solidImage(red: 1, blue: 0)
        let frames = (0..<100).map { _ in AnimatedImage.Frame(image: image, duration: 0.041) }
        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames))
        let decoded = try XCTUnwrap(AnimatedImage(data: data))
        XCTAssertEqual(decoded.frames.reduce(0) { $0 + $1.duration }, 4.1, accuracy: 0.011)
    }

    func testTimelineKeepsTheFinalStaticFrameUntilStop() {
        let durations = GIFFrameTimeline.durations(
            for: [10, 10.04, 10.08], fallbackDuration: 0.04, endTimestamp: 12
        )
        XCTAssertEqual(durations[2], 1.92, accuracy: 0.0001)
        XCTAssertEqual(durations.reduce(0, +), 2, accuracy: 0.0001)
    }

    func testRecordingEncodingUsesSocialShareDecoration() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]

        let data = try XCTUnwrap(AnimatedGIFEncoder.encodeRecording(frames: frames))
        let decoded = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertGreaterThan(decoded.pixelWidth, 4)
        XCTAssertGreaterThan(decoded.pixelHeight, 3)
    }

    func testRecordingEncodingCanKeepOriginalFrames() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]

        let data = try XCTUnwrap(
            AnimatedGIFEncoder.encodeRecording(frames: frames, style: .original)
        )
        let decoded = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertEqual(decoded.pixelWidth, 4)
        XCTAssertEqual(decoded.pixelHeight, 3)
    }

    func testRecordingEncodingCanUseBorderedFrames() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]

        let data = try XCTUnwrap(
            AnimatedGIFEncoder.encodeRecording(frames: frames, style: .bordered)
        )
        let decoded = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertGreaterThan(decoded.pixelWidth, 4)
        XCTAssertGreaterThan(decoded.pixelHeight, 3)
    }

    func testRecordingUsesCustomBorderSizeForEveryFrame() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]
        for style in [ShareStyle.bordered, .dusk] {
            let data = try XCTUnwrap(AnimatedGIFEncoder.encodeRecording(
                frames: frames, style: style, borderSize: ShareBorderSize(pixels: 73)
            ))
            let decoded = try XCTUnwrap(AnimatedImage(data: data))
            XCTAssertEqual(decoded.frames.count, 2)
            for frame in decoded.frames {
                XCTAssertEqual(frame.image.width, 150)
                XCTAssertEqual(frame.image.height, 149)
            }
            XCTAssertEqual(decoded.frames[0].duration, 0.08, accuracy: 0.011)
            XCTAssertEqual(decoded.frames[1].duration, 0.16, accuracy: 0.011)
            let first = try pixel(in: decoded.frames[0].image, x: 4, y: 4)
            let second = try pixel(in: decoded.frames[1].image, x: 4, y: 4)
            XCTAssertEqual(first.red, second.red, accuracy: 8)
            XCTAssertEqual(first.green, second.green, accuracy: 8)
            XCTAssertEqual(first.blue, second.blue, accuracy: 8)
        }
    }

    func testCopyCompletionOnlyWritesTheGIFToTheClipboard() {
        XCTAssertEqual(
            GIFRecordingCompletionPlan(action: .copy),
            GIFRecordingCompletionPlan(
                copiesToClipboard: true,
                presentsSavePanel: false
            )
        )
    }

    func testSaveCompletionOnlyPresentsTheSavePanel() {
        XCTAssertEqual(
            GIFRecordingCompletionPlan(action: .save),
            GIFRecordingCompletionPlan(
                copiesToClipboard: false,
                presentsSavePanel: true
            )
        )
    }

    func testShareCardEncodingUsesStablePaperCanvasAndPreservesAnimation() throws {
        let frames = [
            AnimatedImage.Frame(image: try solidImage(red: 1, blue: 0), duration: 0.08),
            AnimatedImage.Frame(image: try solidImage(red: 0, blue: 1), duration: 0.16)
        ]

        let data = try XCTUnwrap(AnimatedGIFEncoder.encodeShareCard(frames: frames))
        let decoded = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertEqual(decoded.frames.count, 2)
        XCTAssertGreaterThan(decoded.pixelWidth, 4)
        XCTAssertGreaterThan(decoded.pixelHeight, 3)
        XCTAssertEqual(decoded.frames[0].duration, 0.08, accuracy: 0.011)
        XCTAssertEqual(decoded.frames[1].duration, 0.16, accuracy: 0.011)

        let firstBorder = try pixel(in: decoded.frames[0].image, x: 4, y: 4)
        let secondBorder = try pixel(in: decoded.frames[1].image, x: 4, y: 4)
        XCTAssertEqual(firstBorder.red, secondBorder.red, accuracy: 2)
        XCTAssertEqual(firstBorder.green, secondBorder.green, accuracy: 2)
        XCTAssertEqual(firstBorder.blue, secondBorder.blue, accuracy: 2)

        let centerX = decoded.pixelWidth / 2
        let centerY = decoded.pixelHeight / 2
        let firstCenter = try pixel(in: decoded.frames[0].image, x: centerX, y: centerY)
        let secondCenter = try pixel(in: decoded.frames[1].image, x: centerX, y: centerY)
        XCTAssertGreaterThan(firstCenter.red, 220)
        XCTAssertLessThan(firstCenter.blue, 30)
        XCTAssertGreaterThan(secondCenter.blue, 220)
        XCTAssertLessThan(secondCenter.red, 30)
    }

    private func solidImage(red: CGFloat, blue: CGFloat) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }
}
