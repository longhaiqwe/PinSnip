import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PinSnipCore

final class AnimatedImageTests: XCTestCase {
    func testDecodesEveryGIFFrameWithTimingAndLoopInformation() throws {
        let data = try makeGIF(frameDurations: [0.08, 0.16], loopCount: 3)

        let animation = try XCTUnwrap(AnimatedImage(data: data))

        XCTAssertEqual(animation.pixelWidth, 2)
        XCTAssertEqual(animation.pixelHeight, 1)
        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(animation.frames[0].duration, 0.08, accuracy: 0.001)
        XCTAssertEqual(animation.frames[1].duration, 0.16, accuracy: 0.001)
        XCTAssertEqual(animation.loopCount, 3)
    }

    func testRejectsAStillImage() throws {
        let data = try makeGIF(frameDurations: [0.12], loopCount: 0)

        XCTAssertNil(AnimatedImage(data: data))
    }

    private func makeGIF(frameDurations: [Double], loopCount: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.gif.identifier as CFString,
                frameDurations.count,
                nil
            )
        )
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]] as CFDictionary
        )

        for (index, duration) in frameDurations.enumerated() {
            let image = try solidImage(red: index.isMultiple(of: 2) ? 1 : 0)
            let properties = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func solidImage(red: CGFloat) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        return try XCTUnwrap(context.makeImage())
    }
}
