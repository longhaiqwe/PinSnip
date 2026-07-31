import CoreGraphics
import CoreImage
import Foundation

public enum ShareCardRenderer {
    private struct RGBColor {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private struct HSLColor {
        let hue: CGFloat
        let saturation: CGFloat
        let lightness: CGFloat
    }

    private struct PaperPalette {
        let field: RGBColor
        let mainPaper: RGBColor
        let backPaper: RGBColor
    }

    private static let screenshotRotation = CGFloat(-0.28 * .pi / 180)

    public struct Template {
        private let style: ShareStyle
        private let background: CGImage?
        private let contentRect: CGRect
        private let cornerRadius: CGFloat

        public init?(styleSource: CGImage, style: ShareStyle = .paperCut) {
            self.style = style
            if style == .original {
                self.background = nil
                self.contentRect = CGRect(
                    x: 0,
                    y: 0,
                    width: styleSource.width,
                    height: styleSource.height
                )
                self.cornerRadius = 0
                return
            }

            let padding = ShareCardRenderer.canvasPadding(for: styleSource)
            let canvasWidth = styleSource.width + padding * 2
            let canvasHeight = styleSource.height + padding * 2
            guard let context = ShareCardRenderer.makeContext(
                width: canvasWidth,
                height: canvasHeight
            ) else { return nil }

            let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
            let contentRect = canvas.insetBy(dx: CGFloat(padding), dy: CGFloat(padding))
            let cornerRadius = ShareCardRenderer.cornerRadius(for: contentRect)
            switch style {
            case .paperCut:
                let palette = ShareCardRenderer.paperPalette(for: styleSource)
                ShareCardRenderer.drawPaperStack(
                    behind: contentRect,
                    padding: CGFloat(padding),
                    palette: palette,
                    context: context
                )
                ShareCardRenderer.drawScreenshotShadow(
                    in: contentRect,
                    padding: CGFloat(padding),
                    field: palette.field,
                    context: context
                )
            case .bordered:
                ShareCardRenderer.drawBorderBackground(
                    styleSource,
                    in: canvas,
                    padding: CGFloat(padding),
                    context: context
                )
                ShareCardRenderer.drawBorderCardShadow(
                    in: contentRect,
                    cornerRadius: cornerRadius,
                    context: context
                )
            case .original:
                break
            }
            guard let background = context.makeImage() else { return nil }
            self.background = background
            self.contentRect = contentRect
            self.cornerRadius = cornerRadius
        }

        public func render(baseImage: CGImage) -> CGImage? {
            guard style != .original else { return baseImage }
            guard let background else { return nil }
            guard let context = ShareCardRenderer.makeContext(
                width: background.width,
                height: background.height
            ) else { return nil }
            let canvas = CGRect(x: 0, y: 0, width: background.width, height: background.height)
            context.draw(background, in: canvas)
            switch style {
            case .paperCut:
                ShareCardRenderer.drawPaperScreenshotContent(
                    baseImage,
                    in: contentRect,
                    context: context
                )
            case .bordered:
                ShareCardRenderer.drawBorderScreenshotContent(
                    baseImage,
                    in: contentRect,
                    cornerRadius: cornerRadius,
                    context: context
                )
            case .original:
                break
            }
            return context.makeImage()
        }
    }

    public static func render(
        baseImage: CGImage,
        style: ShareStyle = .paperCut
    ) -> CGImage? {
        Template(styleSource: baseImage, style: style)?.render(baseImage: baseImage)
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func canvasPadding(for image: CGImage) -> Int {
        let proportional = Int((CGFloat(min(image.width, image.height)) * 0.1).rounded())
        return min(120, max(24, proportional))
    }

    private static func drawPaperStack(
        behind contentRect: CGRect,
        padding: CGFloat,
        palette: PaperPalette,
        context: CGContext
    ) {
        let mainRect = contentRect
            .insetBy(dx: -padding * 0.28, dy: -padding * 0.29)
            .offsetBy(dx: -padding * 0.02, dy: padding * 0.01)
        let backRect = mainRect
            .insetBy(dx: -padding * 0.025, dy: -padding * 0.025)
            .offsetBy(dx: padding * 0.10, dy: -padding * 0.08)

        drawPaperLayer(
            in: backRect,
            rotation: CGFloat(-1.15 * .pi / 180),
            points: backPaperPoints,
            color: palette.backPaper,
            shadowColor: mix(palette.field, with: RGBColor(red: 0, green: 0, blue: 0), amount: 0.45),
            shadowOffset: CGSize(width: padding * 0.04, height: -padding * 0.16),
            shadowBlur: max(3, padding * 0.22),
            context: context
        )
        drawPaperLayer(
            in: mainRect,
            rotation: CGFloat(0.55 * .pi / 180),
            points: mainPaperPoints,
            color: palette.mainPaper,
            shadowColor: mix(palette.field, with: RGBColor(red: 0, green: 0, blue: 0), amount: 0.32),
            shadowOffset: CGSize(width: padding * 0.08, height: -padding * 0.11),
            shadowBlur: max(2, padding * 0.12),
            context: context
        )
    }

    private static func drawPaperLayer(
        in rect: CGRect,
        rotation: CGFloat,
        points: [CGPoint],
        color: RGBColor,
        shadowColor: RGBColor,
        shadowOffset: CGSize,
        shadowBlur: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        rotateContext(context, by: rotation, around: CGPoint(x: rect.midX, y: rect.midY))
        context.setShadow(
            offset: shadowOffset,
            blur: shadowBlur,
            color: cgColor(shadowColor, alpha: 0.24)
        )
        context.addPath(irregularPath(in: rect, points: points))
        context.setFillColor(cgColor(color))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawScreenshotShadow(
        in rect: CGRect,
        padding: CGFloat,
        field: RGBColor,
        context: CGContext
    ) {
        context.saveGState()
        rotateContext(context, by: screenshotRotation, around: CGPoint(x: rect.midX, y: rect.midY))
        context.setShadow(
            offset: CGSize(width: 0, height: -padding * 0.11),
            blur: max(3, padding * 0.20),
            color: cgColor(field, alpha: 0.34)
        )
        context.addPath(irregularPath(in: rect, points: screenshotPoints))
        context.setFillColor(cgColor(field))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawPaperScreenshotContent(
        _ image: CGImage,
        in rect: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        rotateContext(context, by: screenshotRotation, around: CGPoint(x: rect.midX, y: rect.midY))
        context.addPath(irregularPath(in: rect, points: screenshotPoints))
        context.clip()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func drawBorderBackground(
        _ image: CGImage,
        in canvas: CGRect,
        padding: CGFloat,
        context: CGContext
    ) {
        if let background = blurredAspectFill(image, canvasSize: canvas.size, padding: padding) {
            context.interpolationQuality = .high
            context.draw(background, in: canvas)
        } else {
            context.setFillColor(CGColor(red: 0.12, green: 0.15, blue: 0.28, alpha: 1))
            context.fill(canvas)
        }

        let accent = ambientColor(from: dominantColor(in: image))
        let colors = [
            cgColor(
                mix(accent, with: RGBColor(red: 0.10, green: 0.13, blue: 0.22), amount: 0.28),
                alpha: 0.48
            ),
            cgColor(
                mix(accent, with: RGBColor(red: 0.82, green: 0.78, blue: 0.88), amount: 0.22),
                alpha: 0.34
            )
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: canvas.minX, y: canvas.midY),
                end: CGPoint(x: canvas.maxX, y: canvas.midY),
                options: []
            )
        }

        context.setFillColor(CGColor(gray: 0, alpha: 0.06))
        context.fill(canvas)
    }

    private static func blurredAspectFill(
        _ image: CGImage,
        canvasSize: CGSize,
        padding: CGFloat
    ) -> CGImage? {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = max(
            canvasSize.width / max(1, sourceSize.width),
            canvasSize.height / max(1, sourceSize.height)
        )
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let transform = CGAffineTransform(
            translationX: (canvasSize.width - scaledSize.width) / 2,
            y: (canvasSize.height - scaledSize.height) / 2
        ).scaledBy(x: scale, y: scale)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let input = CIImage(cgImage: image)
            .transformed(by: transform)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: max(18, padding * 0.45))
            .cropped(to: canvas)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(input, from: canvas)
    }

    private static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(32, max(12, min(rect.width, rect.height) * 0.025))
    }

    private static func drawBorderCardShadow(
        in rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        let cardPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -max(2, cornerRadius * 0.15)),
            blur: max(18, cornerRadius * 1.5),
            color: CGColor(gray: 0, alpha: 0.16)
        )
        context.addPath(cardPath)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawBorderScreenshotContent(
        _ image: CGImage,
        in rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        let cardPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()

        context.addPath(cardPath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.34))
        context.setLineWidth(1)
        context.strokePath()
    }

    private static func rotateContext(
        _ context: CGContext,
        by angle: CGFloat,
        around center: CGPoint
    ) {
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        context.translateBy(x: -center.x, y: -center.y)
    }

    private static func irregularPath(in rect: CGRect, points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: point(first, in: rect))
        for normalizedPoint in points.dropFirst() {
            path.addLine(to: point(normalizedPoint, in: rect))
        }
        path.closeSubpath()
        return path
    }

    private static func point(_ normalizedPoint: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalizedPoint.x * rect.width,
            y: rect.minY + normalizedPoint.y * rect.height
        )
    }

    private static let backPaperPoints = [
        CGPoint(x: 0.008, y: 0.020),
        CGPoint(x: 0.35, y: 0.000),
        CGPoint(x: 0.69, y: 0.011),
        CGPoint(x: 0.990, y: 0.002),
        CGPoint(x: 1.000, y: 0.31),
        CGPoint(x: 0.987, y: 0.67),
        CGPoint(x: 0.997, y: 0.986),
        CGPoint(x: 0.65, y: 1.000),
        CGPoint(x: 0.31, y: 0.985),
        CGPoint(x: 0.000, y: 0.994),
        CGPoint(x: 0.010, y: 0.63),
        CGPoint(x: 0.001, y: 0.29)
    ]

    private static let mainPaperPoints = [
        CGPoint(x: 0.002, y: 0.010),
        CGPoint(x: 0.32, y: 0.018),
        CGPoint(x: 0.67, y: 0.000),
        CGPoint(x: 0.992, y: 0.015),
        CGPoint(x: 0.986, y: 0.35),
        CGPoint(x: 0.998, y: 0.70),
        CGPoint(x: 0.989, y: 0.994),
        CGPoint(x: 0.66, y: 0.982),
        CGPoint(x: 0.34, y: 0.998),
        CGPoint(x: 0.006, y: 0.980),
        CGPoint(x: 0.014, y: 0.62),
        CGPoint(x: 0.002, y: 0.29)
    ]

    private static let screenshotPoints = [
        CGPoint(x: -0.004, y: 0.010),
        CGPoint(x: 0.33, y: -0.010),
        CGPoint(x: 0.68, y: 0.002),
        CGPoint(x: 1.004, y: -0.006),
        CGPoint(x: 0.992, y: 0.35),
        CGPoint(x: 0.998, y: 0.68),
        CGPoint(x: 0.994, y: 0.992),
        CGPoint(x: 0.65, y: 1.008),
        CGPoint(x: 0.31, y: 0.990),
        CGPoint(x: -0.003, y: 1.006),
        CGPoint(x: 0.008, y: 0.64),
        CGPoint(x: 0.001, y: 0.31)
    ]

    private static func paperPalette(for image: CGImage) -> PaperPalette {
        let sampled = dominantColor(in: image)
        let sampledHSL = hsl(from: sampled)
        if sampledHSL.saturation < 0.055 {
            return PaperPalette(
                field: RGBColor(red: 0.15, green: 0.20, blue: 0.18),
                mainPaper: RGBColor(red: 0.84, green: 0.87, blue: 0.82),
                backPaper: RGBColor(red: 0.70, green: 0.48, blue: 0.36)
            )
        }

        let accent = ambientColor(from: sampled)
        let accentHSL = hsl(from: accent)
        let fieldSaturation = min(0.46, max(0.30, accentHSL.saturation * 0.62))
        let paperSaturation = min(0.20, max(0.10, accentHSL.saturation * 0.24))
        let backSaturation = min(0.52, max(0.34, accentHSL.saturation * 0.76))
        return PaperPalette(
            field: rgb(hue: accentHSL.hue, saturation: fieldSaturation, lightness: 0.18),
            mainPaper: rgb(hue: accentHSL.hue, saturation: paperSaturation, lightness: 0.84),
            backPaper: rgb(
                hue: wrappedHue(accentHSL.hue + 0.035),
                saturation: backSaturation,
                lightness: 0.61
            )
        )
    }

    private static func dominantColor(in image: CGImage) -> RGBColor {
        let sampleWidth = 64
        let sampleHeight = 64
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return RGBColor(red: 0.42, green: 0.46, blue: 0.56)
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var totalWeight: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let pixelRed = CGFloat(pixels[index]) / 255
            let pixelGreen = CGFloat(pixels[index + 1]) / 255
            let pixelBlue = CGFloat(pixels[index + 2]) / 255
            let maximum = max(pixelRed, pixelGreen, pixelBlue)
            let minimum = min(pixelRed, pixelGreen, pixelBlue)
            let saturation = maximum - minimum
            let luminance = pixelRed * 0.2126 + pixelGreen * 0.7152 + pixelBlue * 0.0722
            let isPaper = luminance > 0.90 && saturation < 0.08
            let isLightNeutral = luminance > 0.68 && saturation < 0.12
            let neutralWeight: CGFloat = isPaper ? 0.015 : isLightNeutral ? 0.025 : 1
            let weight = neutralWeight * (0.30 + saturation * 2 + (1 - luminance) * 0.35)
            red += pixelRed * weight
            green += pixelGreen * weight
            blue += pixelBlue * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else {
            return RGBColor(red: 0.42, green: 0.46, blue: 0.56)
        }
        return RGBColor(red: red / totalWeight, green: green / totalWeight, blue: blue / totalWeight)
    }

    private static func ambientColor(from sampled: RGBColor) -> RGBColor {
        let saturation = max(sampled.red, sampled.green, sampled.blue)
            - min(sampled.red, sampled.green, sampled.blue)
        let neutralAmount: CGFloat = saturation < 0.04 ? 0.55 : 0.08
        let mixed = mix(
            sampled,
            with: RGBColor(red: 0.28, green: 0.33, blue: 0.43),
            amount: neutralAmount
        )
        let mixedChroma = max(mixed.red, mixed.green, mixed.blue)
            - min(mixed.red, mixed.green, mixed.blue)
        let chromaBoost = min(2.2, max(1, 0.32 / max(0.001, mixedChroma)))
        return amplifyChroma(mixed, by: chromaBoost)
    }

    private static func amplifyChroma(_ color: RGBColor, by factor: CGFloat) -> RGBColor {
        let luminance = color.red * 0.2126 + color.green * 0.7152 + color.blue * 0.0722
        return RGBColor(
            red: min(1, max(0, luminance + (color.red - luminance) * factor)),
            green: min(1, max(0, luminance + (color.green - luminance) * factor)),
            blue: min(1, max(0, luminance + (color.blue - luminance) * factor))
        )
    }

    private static func hsl(from color: RGBColor) -> HSLColor {
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0.0001 else {
            return HSLColor(hue: 0, saturation: 0, lightness: lightness)
        }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: CGFloat
        if maximum == color.red {
            hue = ((color.green - color.blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == color.green {
            hue = (((color.blue - color.red) / delta) + 2) / 6
        } else {
            hue = (((color.red - color.green) / delta) + 4) / 6
        }
        return HSLColor(
            hue: wrappedHue(hue),
            saturation: min(1, max(0, saturation)),
            lightness: min(1, max(0, lightness))
        )
    }

    private static func rgb(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) -> RGBColor {
        guard saturation > 0.0001 else {
            return RGBColor(red: lightness, green: lightness, blue: lightness)
        }
        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        return RGBColor(
            red: hueChannel(p: p, q: q, hue: hue + 1 / 3),
            green: hueChannel(p: p, q: q, hue: hue),
            blue: hueChannel(p: p, q: q, hue: hue - 1 / 3)
        )
    }

    private static func hueChannel(p: CGFloat, q: CGFloat, hue: CGFloat) -> CGFloat {
        let hue = wrappedHue(hue)
        if hue < 1 / 6 { return p + (q - p) * 6 * hue }
        if hue < 1 / 2 { return q }
        if hue < 2 / 3 { return p + (q - p) * (2 / 3 - hue) * 6 }
        return p
    }

    private static func wrappedHue(_ hue: CGFloat) -> CGFloat {
        let remainder = hue.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private static func mix(_ color: RGBColor, with other: RGBColor, amount: CGFloat) -> RGBColor {
        RGBColor(
            red: color.red + (other.red - color.red) * amount,
            green: color.green + (other.green - color.green) * amount,
            blue: color.blue + (other.blue - color.blue) * amount
        )
    }

    private static func cgColor(_ color: RGBColor, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [color.red, color.green, color.blue, alpha]
        )!
    }
}
