import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationRendererTests: XCTestCase {
    func testOriginalShareStyleReturnsTheUnmodifiedScreenshot() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 12, green: 130, blue: 220))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .original))

        XCTAssertEqual(rendered.width, 80)
        XCTAssertEqual(rendered.height, 60)
        let corner = try XCTUnwrap(pixel(in: rendered, x: 4, y: 4))
        XCTAssertEqual(corner.red, 12)
        XCTAssertEqual(corner.green, 130)
        XCTAssertEqual(corner.blue, 220)
        XCTAssertEqual(corner.alpha, 255)
    }

    func testBorderedShareStyleUsesAnOpaqueCanvas() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 240, green: 80, blue: 40))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .bordered))

        XCTAssertEqual(rendered.width, 128)
        XCTAssertEqual(rendered.height, 108)
        let canvasCorner = try XCTUnwrap(pixel(in: rendered, x: 4, y: 4))
        XCTAssertEqual(canvasCorner.alpha, 255)
        let center = try XCTUnwrap(pixel(in: rendered, x: 64, y: 54))
        XCTAssertEqual(center.red, 240, accuracy: 2)
        XCTAssertEqual(center.green, 80, accuracy: 2)
        XCTAssertEqual(center.blue, 40, accuracy: 2)
    }

    func testShareCardLeavesCanvasTransparentOutsidePaperCutout() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 240, green: 80, blue: 40))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .paperCut))

        XCTAssertEqual(rendered.width, 128)
        XCTAssertEqual(rendered.height, 108)
        let outsidePaper = try XCTUnwrap(pixel(in: rendered, x: 4, y: 4))
        XCTAssertEqual(outsidePaper.alpha, 0)
    }

    func testShareCardUsesScreenshotDominantColorForBackPaper() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 240, green: 80, blue: 40))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let backPaper = try XCTUnwrap(pixel(in: rendered, x: 110, y: 54))
        XCTAssertEqual(backPaper.alpha, 255)
        XCTAssertGreaterThan(Int(backPaper.red), Int(backPaper.blue) + 25)
    }

    func testShareCardBackPaperUsesSparseAccentFromLightScreenshot() throws {
        let base = try XCTUnwrap(makeLightImageWithRedAccents(width: 200, height: 120))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let backPaper = try XCTUnwrap(pixel(in: rendered, x: 230, y: 84))
        XCTAssertGreaterThan(Int(backPaper.red), Int(backPaper.blue) + 30)
    }

    func testShareCardBackPaperPreservesMutedBlueAccent() throws {
        let base = try XCTUnwrap(makeLightImageWithMutedBlueAccents(width: 200, height: 120))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let backPaper = try XCTUnwrap(pixel(in: rendered, x: 230, y: 84))
        XCTAssertGreaterThanOrEqual(Int(backPaper.blue) - Int(backPaper.red), 25)
    }

    func testShareCardUsesStableWarmBackPaperForNeutralScreenshot() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, gray: 1))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let backPaper = try XCTUnwrap(pixel(in: rendered, x: 110, y: 54))
        XCTAssertEqual(backPaper.alpha, 255)
        XCTAssertGreaterThan(Int(backPaper.red), Int(backPaper.blue) + 25)
    }

    func testShareCardKeepsLightPaperLayerBehindScreenshot() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 240, green: 80, blue: 40))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let lightPaper = try XCTUnwrap(pixel(in: rendered, x: 64, y: 18))
        let brightness = Int(lightPaper.red) + Int(lightPaper.green) + Int(lightPaper.blue)
        XCTAssertEqual(lightPaper.alpha, 255)
        XCTAssertGreaterThan(brightness, 500)
    }

    func testShareCardDoesNotAddWhiteBorderAlongScreenshotEdge() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 240, green: 80, blue: 40))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let screenshotEdge = try XCTUnwrap(pixel(in: rendered, x: 64, y: 24))
        XCTAssertEqual(screenshotEdge.red, 240, accuracy: 4)
        XCTAssertEqual(screenshotEdge.green, 80, accuracy: 4)
        XCTAssertEqual(screenshotEdge.blue, 40, accuracy: 4)
    }

    func testShareCardKeepsScreenshotCenterColor() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 12, green: 130, blue: 220))

        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base))

        let center = try XCTUnwrap(pixel(in: rendered, x: 64, y: 54))
        XCTAssertEqual(center.red, 12, accuracy: 2)
        XCTAssertEqual(center.green, 130, accuracy: 2)
        XCTAssertEqual(center.blue, 220, accuracy: 2)
    }

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
        let channel: UInt8 = gray == 0 ? 0 : 255
        return makeSolidImage(width: width, height: height, red: channel, green: channel, blue: channel)
    }

    private func makeSolidImage(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [
                    CGFloat(red) / 255,
                    CGFloat(green) / 255,
                    CGFloat(blue) / 255,
                    1
                ]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func makeLightImageWithRedAccents(width: Int, height: Int) -> CGImage? {
        makeLightImageWithAccents(
            width: width,
            height: height,
            color: CGColor(red: 0.92, green: 0.16, blue: 0.12, alpha: 1)
        )
    }

    private func makeLightImageWithMutedBlueAccents(width: Int, height: Int) -> CGImage? {
        makeLightImageWithAccents(
            width: width,
            height: height,
            color: CGColor(red: 0.43, green: 0.50, blue: 0.58, alpha: 1)
        )
    }

    private func makeLightImageWithAccents(
        width: Int,
        height: Int,
        color: CGColor
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.82, alpha: 1))
        for y in stride(from: 8, to: height, by: 16) {
            context.fill(CGRect(x: 8, y: y, width: width - 16, height: 8))
        }
        context.setFillColor(color)
        context.fill(CGRect(x: 18, y: 22, width: 5, height: 76))
        context.fill(CGRect(x: 58, y: 82, width: 70, height: 5))
        context.fill(CGRect(x: 146, y: 34, width: 34, height: 8))
        return context.makeImage()
    }

    private func pixel(
        in image: CGImage,
        x: Int,
        y: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
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
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }
}
