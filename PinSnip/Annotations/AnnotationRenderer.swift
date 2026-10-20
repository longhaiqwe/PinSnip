import CoreGraphics
import CoreText
import Foundation

public enum AnnotationRenderer {
    nonisolated(unsafe) private static var fontCache: [CGFloat: CTFont] = [:]
    nonisolated(unsafe) private static var boldFontCache: [CGFloat: CTFont] = [:]

    private static func cachedFont(size: CGFloat) -> CTFont {
        let size = max(8, size)
        if let cached = fontCache[size] { return cached }
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        fontCache[size] = font
        return font
    }

    private static func cachedBoldFont(size: CGFloat) -> CTFont {
        let size = max(8, size)
        if let cached = boldFontCache[size] { return cached }
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        boldFontCache[size] = font
        return font
    }

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

        case let .arrow(from, to, color, width, style):
            drawArrow(from: from, to: to, color: color, width: width, style: style, in: context)

        case let .text(rect, text, color, fontSize):
            drawText(text, rect: rect, color: color, fontSize: fontSize, in: context)

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

    /// Shared by the live overlay, style thumbnails and exported image.
    public static func drawArrow(
        from: CGPoint, to: CGPoint, color: RGBAColor, width: CGFloat,
        style: ArrowAnnotationStyle, in context: CGContext
    ) {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length.isFinite, length > 0, width.isFinite, width > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        configure(context, color: color, width: width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let ux = (to.x - from.x) / length
        let uy = (to.y - from.y) / length
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: from.x + ux * x - uy * y, y: from.y + uy * x + ux * y)
        }
        context.beginPath()
        if style == .line {
            let headLength = min(width * 4, length * 0.6)
            let spread = CGFloat.pi / 7
            context.move(to: from)
            context.addLine(to: to)
            context.move(to: point(length - headLength * cos(spread), headLength * sin(spread)))
            context.addLine(to: to)
            context.addLine(to: point(length - headLength * cos(spread), -headLength * sin(spread)))
            context.strokePath()
            return
        }

        // Scale the entire silhouette for short drags, retaining an open interior.
        let unit = min(width, length / 10)
        let shaft = unit * 1.5
        let head = unit * 4
        let neck = length - unit * 7
        context.move(to: point(0, shaft))
        context.addLine(to: point(neck, shaft))
        context.addLine(to: point(neck, head))
        context.addLine(to: to)
        context.addLine(to: point(neck, -head))
        context.addLine(to: point(neck, -shaft))
        context.addLine(to: point(0, -shaft))
        context.closePath()
        if style == .hollow {
            context.setLineWidth(unit * 0.65)
            context.strokePath()
        } else {
            context.setFillColor(cgColor(color))
            context.fillPath()
        }
    }

    public static func drawText(
        _ text: String,
        rect: CGRect,
        color: RGBAColor,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        guard !text.isEmpty else { return }
        let font = cachedFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(color)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGPath(rect: TextAnnotationLayout.contentRect(in: rect), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )

        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    public static func suggestedTextBoxHeight(
        for text: String,
        width: CGFloat,
        fontSize: CGFloat
    ) -> CGFloat {
        let font = cachedFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let framesetter = CTFramesetterCreateWithAttributedString(
            NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes)
        )
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(
                width: TextAnnotationLayout.effectiveContentWidth(for: width),
                height: .greatestFiniteMagnitude
            ),
            nil
        )
        let verticalInsets = TextAnnotationLayout.verticalTextInset * 2
        return max(
            ceil(suggested.height + verticalInsets),
            ceil(max(8, fontSize) * 1.25 + verticalInsets)
        )
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
        let font = cachedBoldFont(size: fontSize)
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
