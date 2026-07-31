import CoreGraphics
import CoreText
import Foundation

public enum AnnotationRenderer {
    public static func render(baseImage: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: baseImage.width,
            height: baseImage.height,
            bitsPerComponent: 8,
            bytesPerRow: baseImage.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        context.draw(baseImage, in: canvas)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)

        var cachedMosaicImages: [CGFloat: CGImage] = [:]
        func getMosaicImage(pixelSize: CGFloat) -> CGImage? {
            let size = max(2, pixelSize)
            if let existing = cachedMosaicImages[size] { return existing }
            guard let created = createMosaicImage(from: baseImage, pixelSize: size) else { return nil }
            cachedMosaicImages[size] = created
            return created
        }

        for annotation in annotations {
            draw(annotation, in: context, canvas: canvas, getMosaicImage: getMosaicImage)
        }
        return context.makeImage()
    }

    public static func createMosaicImage(from baseImage: CGImage, pixelSize: CGFloat) -> CGImage? {
        let scale = max(2, pixelSize)
        let smallWidth = max(1, Int(CGFloat(baseImage.width) / scale))
        let smallHeight = max(1, Int(CGFloat(baseImage.height) / scale))

        guard let smallContext = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: 8,
            bytesPerRow: smallWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        smallContext.interpolationQuality = .none
        smallContext.draw(baseImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let smallImage = smallContext.makeImage() else { return nil }

        guard let mosaicContext = CGContext(
            data: nil,
            width: baseImage.width,
            height: baseImage.height,
            bitsPerComponent: 8,
            bytesPerRow: baseImage.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        mosaicContext.interpolationQuality = .none
        mosaicContext.draw(smallImage, in: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        return mosaicContext.makeImage()
    }

    private static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        canvas: CGRect,
        getMosaicImage: (CGFloat) -> CGImage?
    ) {
        switch annotation {
        case let .rectangle(rect, color, width):
            configure(context, color: color, width: width)
            context.stroke(rect.insetBy(dx: width / 2, dy: width / 2))

        case let .pencil(points, color, width):
            guard let first = points.first else { return }
            configure(context, color: color, width: width)
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()

        case let .arrow(from, to, color, width):
            configure(context, color: color, width: width)
            context.beginPath()
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()

            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(10, width * 4)
            let spread = CGFloat.pi / 7
            let left = CGPoint(
                x: to.x - headLength * cos(angle - spread),
                y: to.y - headLength * sin(angle - spread)
            )
            let right = CGPoint(
                x: to.x - headLength * cos(angle + spread),
                y: to.y - headLength * sin(angle + spread)
            )
            context.beginPath()
            context.move(to: left)
            context.addLine(to: to)
            context.addLine(to: right)
            context.strokePath()

        case let .number(center, value, color, diameter):
            drawNumber(
                value,
                center: center,
                color: color,
                diameter: diameter,
                in: context
            )

        case let .mosaic(rect, pixelSize):
            guard let mosaicImage = getMosaicImage(pixelSize) else { return }
            context.saveGState()
            context.clip(to: rect)
            context.draw(mosaicImage, in: canvas)
            context.restoreGState()

        case let .mosaicPencil(points, width):
            guard let mosaicImage = getMosaicImage(16), let first = points.first else { return }
            context.saveGState()
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.setLineWidth(max(1, width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            context.draw(mosaicImage, in: canvas)
            context.restoreGState()
        }
    }

    private static func drawNumber(
        _ value: Int,
        center: CGPoint,
        color: RGBAColor,
        diameter: CGFloat,
        in context: CGContext
    ) {
        let diameter = max(16, diameter)
        let badgeRect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.setFillColor(cgColor(color))
        context.fillEllipse(in: badgeRect)

        let digits = String(value)
        let fontScale: CGFloat = digits.count >= 3 ? 0.38 : digits.count == 2 ? 0.45 : 0.52
        let fontSize = diameter * fontScale
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: digits, attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: center.x - width / 2,
            y: center.y - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func configure(_ context: CGContext, color: RGBAColor, width: CGFloat) {
        context.setStrokeColor(cgColor(color))
        context.setLineWidth(max(1, width))
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [color.red, color.green, color.blue, color.alpha]
        )!
    }
}
