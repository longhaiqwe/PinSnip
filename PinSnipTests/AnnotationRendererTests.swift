import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationRendererTests: XCTestCase {
    func testHollowArrowPreservesBackgroundInsideShaftAndHead() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 200, height: 100, red: 12, green: 130, blue: 220))
        let rendered = try XCTUnwrap(AnnotationRenderer.render(baseImage: base, annotations: [
            .arrow(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 180, y: 50),
                   RGBAColor(red: 1, green: 0, blue: 0), 3, style: .hollow)
        ]))
        for x in [60, 165] {
            let interior = try XCTUnwrap(pixel(in: rendered, x: x, y: 50))
            XCTAssertEqual(interior.red, 12, accuracy: 1)
            XCTAssertEqual(interior.green, 130, accuracy: 1)
            XCTAssertEqual(interior.blue, 220, accuracy: 1)
        }
        let outline = try XCTUnwrap(pixel(in: rendered, x: 60, y: 45))
        XCTAssertGreaterThan(outline.red, 230)
        XCTAssertLessThan(outline.blue, 25)
    }

    func testFilledArrowHasOpaqueShaftAndZeroLengthArrowDrawsNothing() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 200, height: 100, red: 12, green: 130, blue: 220))
        for style in ArrowAnnotationStyle.allCases {
            let empty = try XCTUnwrap(AnnotationRenderer.render(baseImage: base, annotations: [
                .arrow(from: CGPoint(x: 60, y: 50), to: CGPoint(x: 60, y: 50), .white, 3, style: style)
            ]))
            let center = try XCTUnwrap(pixel(in: empty, x: 60, y: 50))
            XCTAssertEqual(center.red, 12)
            XCTAssertEqual(center.blue, 220)
        }
        let filled = try XCTUnwrap(AnnotationRenderer.render(baseImage: base, annotations: [
            .arrow(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 180, y: 50), .white, 3, style: .filled)
        ]))
        XCTAssertEqual(try XCTUnwrap(pixel(in: filled, x: 60, y: 50)).red, 255)
    }

    func testArrowStylesSurviveCropAndScale() {
        for style in ArrowAnnotationStyle.allCases {
            let annotation = Annotation.arrow(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 80, y: 90),
                                              .white, 3, style: style)
            XCTAssertEqual(annotation.mapped(relativeTo: CGPoint(x: 10, y: 20), scale: 2),
                           .arrow(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 140, y: 140),
                                  .white, 6, style: style))
        }
    }

    func testCustomPaddingAppliesToAllBackgroundsAndPreservesScreenshotPixels() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, red: 12, green: 130, blue: 220))
        for style in ShareStyle.allCases where style != .original {
            for padding in [8, 73, 300] {
                let rendered = try XCTUnwrap(ShareCardRenderer.render(
                    baseImage: base, style: style, borderSize: ShareBorderSize(pixels: padding)
                ))
                XCTAssertEqual(rendered.width, 80 + padding * 2)
                XCTAssertEqual(rendered.height, 60 + padding * 2)
                let center = try XCTUnwrap(pixel(in: rendered, x: padding + 40, y: padding + 30))
                XCTAssertEqual(center.red, 12, accuracy: 2)
                XCTAssertEqual(center.green, 130, accuracy: 2)
                XCTAssertEqual(center.blue, 220, accuracy: 2)
                XCTAssertEqual(try XCTUnwrap(pixel(in: rendered, x: 0, y: 0)).alpha, 255)
            }
        }
    }

    func testDuskBackgroundDoesNotChangeWithScreenshotColors() throws {
        let red = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 255, green: 0, blue: 0))
        let blue = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 0, green: 0, blue: 255))
        let first = try XCTUnwrap(ShareCardRenderer.render(baseImage: red, style: .dusk))
        let second = try XCTUnwrap(ShareCardRenderer.render(baseImage: blue, style: .dusk))
        for point in [(4, 4), (first.width - 5, 4), (first.width / 2, first.height - 5)] {
            let a = try XCTUnwrap(pixel(in: first, x: point.0, y: point.1))
            let b = try XCTUnwrap(pixel(in: second, x: point.0, y: point.1))
            XCTAssertEqual(a.red, b.red)
            XCTAssertEqual(a.green, b.green)
            XCTAssertEqual(a.blue, b.blue)
            XCTAssertEqual(a.alpha, 255)
        }
        let left = try XCTUnwrap(pixel(in: first, x: 4, y: first.height / 2))
        let top = try XCTUnwrap(pixel(in: first, x: first.width * 2 / 3, y: 4))
        XCTAssertGreaterThan(left.blue, left.red)
        XCTAssertGreaterThan(top.red, top.blue)
    }

    func testBorderSizeDoesNotChangeOriginalDimensions() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 80, height: 60, gray: 1))
        for style in [ShareStyle.original] {
            let automatic = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: style))
            let custom = try XCTUnwrap(ShareCardRenderer.render(
                baseImage: base, style: style, borderSize: ShareBorderSize(pixels: 100)
            ))
            XCTAssertEqual(custom.width, automatic.width)
            XCTAssertEqual(custom.height, automatic.height)
        }
    }

    func testRenderingPreservesTransparentWindowCorners() throws {
        let base = try XCTUnwrap(makeImageWithTransparentCorners(width: 40, height: 30))

        let rendered = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [])
        )

        XCTAssertEqual(try XCTUnwrap(pixel(in: rendered, x: 0, y: 0)).alpha, 0)
        XCTAssertEqual(try XCTUnwrap(pixel(in: rendered, x: 20, y: 15)).alpha, 255)
    }

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

    func testAutomaticBackgroundKeepsNeutralScreenshotsNeutralAndMatchesBrightness() throws {
        var brightness: [Int] = []
        for gray: UInt8 in [0, 1] {
            let base = try XCTUnwrap(makeSolidImage(width: 160, height: 100, gray: gray))
            let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .bordered))
            let corner = try XCTUnwrap(pixel(in: rendered, x: 0, y: 0))
            XCTAssertEqual(corner.alpha, 255)
            XCTAssertEqual(corner.red, corner.green, accuracy: 1)
            XCTAssertEqual(corner.green, corner.blue, accuracy: 1)
            brightness.append(Int(corner.red))
        }
        XCTAssertLessThan(brightness[0], 100)
        XCTAssertGreaterThan(brightness[1], 200)
    }

    func testAutomaticBackgroundSelectsMajorHueInsteadOfMixingOpposingColors() throws {
        let base = try adaptiveFixture(background: CGColor(red: 1, green: 0, blue: 0, alpha: 1), patches: [
            (CGRect(x: 0, y: 0, width: 40, height: 100), CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ])
        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .bordered))
        let corner = try XCTUnwrap(pixel(in: rendered, x: 0, y: 0))
        XCTAssertGreaterThan(Int(corner.red), Int(corner.blue) + 20)
        XCTAssertLessThan(abs(Int(corner.green) - Int(corner.blue)), 25)
    }

    func testAutomaticBackgroundUsesBlueAccentDespiteNeutralText() throws {
        let base = try adaptiveFixture(background: CGColor(gray: 1, alpha: 1), patches: [
            (CGRect(x: 0, y: 0, width: 160, height: 20), CGColor(gray: 0.1, alpha: 1)),
            (CGRect(x: 20, y: 40, width: 30, height: 20), CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1))
        ])
        let rendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: base, style: .bordered))
        let corner = try XCTUnwrap(pixel(in: rendered, x: 0, y: 0))
        XCTAssertGreaterThan(Int(corner.blue), Int(corner.red) + 15)
        XCTAssertGreaterThan(corner.red, 170)
    }

    func testAutomaticBackgroundIgnoresTinyIconsAndTransparentPixels() throws {
        let icon = try adaptiveFixture(background: CGColor(gray: 1, alpha: 1), patches: [
            (CGRect(x: 20, y: 20, width: 4, height: 4), CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ])
        let iconRendered = try XCTUnwrap(ShareCardRenderer.render(baseImage: icon, style: .bordered))
        let neutral = try XCTUnwrap(pixel(in: iconRendered, x: 0, y: 0))
        XCTAssertEqual(neutral.red, neutral.green, accuracy: 1)
        let blue = CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1)
        let solid = try adaptiveFixture(background: blue, patches: [])
        let transparent = try adaptiveFixture(background: CGColor(gray: 0, alpha: 0), patches: [
            (CGRect(x: 40, y: 25, width: 80, height: 50), blue)
        ])
        let opaqueOutput = try XCTUnwrap(ShareCardRenderer.render(baseImage: solid, style: .bordered))
        let transparentOutput = try XCTUnwrap(ShareCardRenderer.render(baseImage: transparent, style: .bordered))
        let first = try XCTUnwrap(pixel(in: opaqueOutput, x: 0, y: 0))
        let second = try XCTUnwrap(pixel(in: transparentOutput, x: 0, y: 0))
        XCTAssertEqual(first.red, second.red, accuracy: 3)
        XCTAssertEqual(first.green, second.green, accuracy: 3)
        XCTAssertEqual(first.blue, second.blue, accuracy: 3)
        XCTAssertEqual(second.alpha, 255)
    }

    func testAutomaticBackgroundRemainsStableWhenAnimationContentChanges() throws {
        let red = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 240, green: 30, blue: 20))
        let blue = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 20, green: 50, blue: 240))
        let template = try XCTUnwrap(ShareCardRenderer.Template(styleSource: red, style: .bordered))
        let first = try XCTUnwrap(template.render(baseImage: red))
        let next = try XCTUnwrap(template.render(baseImage: blue))
        let a = try XCTUnwrap(pixel(in: first, x: 0, y: 0))
        let b = try XCTUnwrap(pixel(in: next, x: 0, y: 0))
        XCTAssertEqual(a.red, b.red)
        XCTAssertEqual(a.green, b.green)
        XCTAssertEqual(a.blue, b.blue)
        XCTAssertEqual(try XCTUnwrap(pixel(in: next, x: next.width / 2, y: next.height / 2)).blue, 240)
    }

    private func adaptiveFixture(background: CGColor, patches: [(CGRect, CGColor)]) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 160 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        for (rect, color) in patches {
            context.setFillColor(color)
            context.fill(rect)
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testGradientBackgroundsAreOpaqueDistinctAndStableAcrossFrames() throws {
        let red = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 255, green: 0, blue: 0))
        let blue = try XCTUnwrap(makeSolidImage(width: 160, height: 100, red: 0, green: 0, blue: 255))
        var signatures = Set<String>()
        for style in ShareStyle.allCases where style != .original && style != .bordered {
            let template = try XCTUnwrap(ShareCardRenderer.Template(styleSource: red, style: style))
            let first = try XCTUnwrap(template.render(baseImage: red))
            let next = try XCTUnwrap(template.render(baseImage: blue))
            let independent = try XCTUnwrap(ShareCardRenderer.render(baseImage: blue, style: style))
            var signature = ""
            for point in [(0, 0), (first.width - 1, 0), (0, first.height - 1), (first.width - 1, first.height - 1)] {
                let a = try XCTUnwrap(pixel(in: first, x: point.0, y: point.1))
                XCTAssertEqual(a.alpha, 255)
                signature += "\(a.red),\(a.green),\(a.blue);"
                for frame in [next, independent] {
                    let b = try XCTUnwrap(pixel(in: frame, x: point.0, y: point.1))
                    XCTAssertEqual(a.red, b.red)
                    XCTAssertEqual(a.green, b.green)
                    XCTAssertEqual(a.blue, b.blue)
                    XCTAssertEqual(b.alpha, 255)
                }
            }
            XCTAssertTrue(signatures.insert(signature).inserted, "Duplicate gradient: \(style)")
            let center = try XCTUnwrap(pixel(in: next, x: next.width / 2, y: next.height / 2))
            XCTAssertEqual(center.blue, 255)
            XCTAssertEqual(center.red, 0)
        }
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

    func testTextAnnotationRendersVisibleColoredGlyphs() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 96, height: 64, gray: 1))
        let annotation = Annotation.text(
            rect: CGRect(x: 8, y: 8, width: 72, height: 36),
            text: "Text",
            color: RGBAColor(red: 1, green: 0, blue: 0),
            fontSize: 24
        )

        let rendered = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [annotation])
        )
        let textPixels = try (8...48).flatMap { y in
            try (6...72).map { x in
                try XCTUnwrap(pixel(in: rendered, x: x, y: y))
            }
        }

        XCTAssertTrue(
            textPixels.contains { $0.red > 200 && $0.green < 120 && $0.blue < 120 },
            "Expected visible red glyph pixels in the text annotation area"
        )
    }

    func testNarrowTextBoxWrapsAcrossMoreVerticalPixelsThanWideTextBox() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 240, height: 120, gray: 1))
        let color = RGBAColor(red: 1, green: 0, blue: 0)
        let text = "Text Text Text Text"
        let narrow = Annotation.text(
            rect: CGRect(x: 8, y: 8, width: 62, height: 96),
            text: text,
            color: color,
            fontSize: 20
        )
        let wide = Annotation.text(
            rect: CGRect(x: 8, y: 8, width: 210, height: 96),
            text: text,
            color: color,
            fontSize: 20
        )

        let narrowImage = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [narrow])
        )
        let wideImage = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [wide])
        )

        XCTAssertGreaterThan(
            try coloredVerticalSpan(in: narrowImage),
            try coloredVerticalSpan(in: wideImage) + 10
        )
    }

    func testTextAnnotationUsesChosenColor() throws {
        let base = try XCTUnwrap(makeSolidImage(width: 120, height: 64, gray: 1))
        let annotation = Annotation.text(
            rect: CGRect(x: 8, y: 8, width: 100, height: 40),
            text: "Blue",
            color: RGBAColor(red: 0.05, green: 0.2, blue: 0.95),
            fontSize: 24
        )
        let rendered = try XCTUnwrap(
            AnnotationRenderer.render(baseImage: base, annotations: [annotation])
        )

        let pixels = try (0..<rendered.height).flatMap { y in
            try (0..<rendered.width).map { x in
                try XCTUnwrap(pixel(in: rendered, x: x, y: y))
            }
        }
        XCTAssertTrue(pixels.contains { $0.blue > 180 && $0.red < 150 })
    }

    private func coloredVerticalSpan(in image: CGImage) throws -> Int {
        var rows: [Int] = []
        for y in 0..<image.height {
            let containsColor = try (0..<image.width).contains { x in
                let value = try XCTUnwrap(pixel(in: image, x: x, y: y))
                return value.red > 200 && value.green < 150 && value.blue < 150
            }
            if containsColor { rows.append(y) }
        }
        guard let first = rows.first, let last = rows.last else { return 0 }
        return last - first + 1
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

    private func makeImageWithTransparentCorners(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
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
