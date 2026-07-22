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
}
