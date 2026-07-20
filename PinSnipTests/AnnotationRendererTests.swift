import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationRendererTests: XCTestCase {
    func testRectangleChangesBorderPixelsButLeavesCenterUntouched() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 32, height: 32, gray: 1))
        let annotation = Annotation.rectangle(
            CGRect(x: 4, y: 4, width: 24, height: 24),
            RGBAColor(red: 1, green: 0, blue: 0),
            2
        )

        let rendered = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [annotation])
        )

        let border = try XCTUnwrap(pixel(in: rendered, x: 4, y: 4))
        let center = try XCTUnwrap(pixel(in: rendered, x: 16, y: 16))
        XCTAssertGreaterThan(border.red, 220)
        XCTAssertLessThan(border.green, 80)
        XCTAssertGreaterThan(center.red, 245)
        XCTAssertGreaterThan(center.green, 245)
        XCTAssertGreaterThan(center.blue, 245)
    }

    func testSequenceNumberRendersColoredBadgeWithWhiteDigit() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 48, height: 48, gray: 1))
        let annotation = Annotation.number(
            center: CGPoint(x: 24, y: 24),
            value: 8,
            color: RGBAColor(red: 1, green: 0, blue: 0),
            diameter: 24
        )

        let rendered = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [annotation])
        )

        let badge = try XCTUnwrap(pixel(in: rendered, x: 16, y: 24))
        XCTAssertGreaterThan(badge.red, 220)
        XCTAssertLessThan(badge.green, 80)
        XCTAssertLessThan(badge.blue, 80)

        let glyphPixels = try (18...30).flatMap { y in
            try (18...30).map { x in
                try XCTUnwrap(pixel(in: rendered, x: x, y: y))
            }
        }
        XCTAssertTrue(
            glyphPixels.contains { $0.red > 220 && $0.green > 220 && $0.blue > 220 },
            "Expected a white sequence-number glyph inside the badge"
        )
    }

    private func makeSolidImage(width: Int, height: Int, gray: UInt8) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: CGFloat(gray), green: CGFloat(gray), blue: CGFloat(gray), alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(-x), y: CGFloat(y - image.height + 1))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }
}
