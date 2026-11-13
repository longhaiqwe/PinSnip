import CoreGraphics
import Foundation

public enum ShareCardRenderer {
    public struct Template {
        private let style: ShareStyle
        private let background: CGImage?
        private let contentRect: CGRect
        private let cornerRadius: CGFloat

        public init?(
            styleSource: CGImage,
            style: ShareStyle = .dusk,
            borderSize: ShareBorderSize = .automatic
        ) {
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

            let padding = borderSize.padding(width: styleSource.width, height: styleSource.height)
            let canvasWidth = styleSource.width + padding * 2
            let canvasHeight = styleSource.height + padding * 2
            guard let context = ShareCardRenderer.makeContext(
                width: canvasWidth,
                height: canvasHeight
            ) else { return nil }

            let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
            let contentRect = canvas.insetBy(dx: CGFloat(padding), dy: CGFloat(padding))
            let cornerRadius = ShareCardRenderer.cornerRadius(for: contentRect)
            if style == .bordered {
                ShareCardRenderer.drawBorderBackground(
                    styleSource, in: canvas, context: context
                )
            } else {
                ShareCardRenderer.drawGradientBackground(style: style, in: canvas, context: context)
            }
            ShareCardRenderer.drawBorderCardShadow(
                in: contentRect, cornerRadius: cornerRadius, context: context
            )
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
            ShareCardRenderer.drawBorderScreenshotContent(
                baseImage, in: contentRect, cornerRadius: cornerRadius, context: context
            )
            return context.makeImage()
        }
    }

    public static func render(
        baseImage: CGImage,
        style: ShareStyle = .dusk,
        borderSize: ShareBorderSize = .automatic
    ) -> CGImage? {
        Template(styleSource: baseImage, style: style, borderSize: borderSize)?.render(baseImage: baseImage)
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

    private static func drawBorderBackground(
        _ image: CGImage,
        in canvas: CGRect,
        context: CGContext
    ) {
        let palette = adaptivePalette(in: image)
        let colors = [
            palette.color(lightnessOffset: 0.045, chromaScale: 0.8),
            palette.color(lightnessOffset: 0, chromaScale: 1),
            palette.color(lightnessOffset: -0.055, chromaScale: 0.9)
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray, locations: [0, 0.5, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: canvas.minX, y: canvas.maxY),
            end: CGPoint(x: canvas.maxX, y: canvas.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawGradientBackground(
        style: ShareStyle, in canvas: CGRect, context: CGContext
    ) {
        if style == .dusk {
            drawDuskBackground(in: canvas, context: context)
            return
        }
        let stops: [UInt32]
        switch style {
        case .ocean: stops = [0xB5E9EE, 0x5CACE0, 0x4655AD]
        case .lavender: stops = [0xEEE2F5, 0xC0AFE5, 0x8A9DD3]
        case .peach: stops = [0xFFF0D9, 0xF5BEA4, 0xDB8D9C]
        case .mint: stops = [0xE7F0D7, 0xA3D4C1, 0x4B9697]
        case .rose: stops = [0xF8E1ED, 0xDDA6C1, 0xA67BAA]
        case .graphite: stops = [0x677583, 0x3B4656, 0x1D2432]
        case .bordered, .dusk, .original: return
        }
        let colors = stops.map { hex in
            CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray, locations: [0, 0.5, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: canvas.minX, y: canvas.maxY),
            end: CGPoint(x: canvas.maxX, y: canvas.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    /// Deep navy, burnt orange and burgundy, independent of screenshot content.
    private static func drawDuskBackground(in canvas: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: canvas.width, y: canvas.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let base = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.035, green: 0.067, blue: 0.102, alpha: 1),
            CGColor(red: 0.067, green: 0.082, blue: 0.114, alpha: 1),
            CGColor(red: 0.27, green: 0.12, blue: 0.22, alpha: 1)
        ] as CFArray, locations: [0, 0.4, 1])!
        context.drawLinearGradient(base, start: CGPoint(x: 0, y: 0.5),
                                   end: CGPoint(x: 1, y: 0.5), options: [])

        // An elliptical warm glow across the upper right, fading into the navy base.
        context.translateBy(x: 0.68, y: 0.96)
        context.scaleBy(x: 0.57, y: 1.15)
        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.65, green: 0.29, blue: 0.19, alpha: 0.94),
            CGColor(red: 0.58, green: 0.25, blue: 0.20, alpha: 0.54),
            CGColor(red: 0.40, green: 0.19, blue: 0.23, alpha: 0)
        ] as CFArray, locations: [0, 0.43, 1])!
        context.drawRadialGradient(glow, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [])
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

    // Oklab separates perceived lightness from hue and chroma.
    // Conversion matrices: https://bottosson.github.io/posts/oklab/ (public domain).
    private struct LabColor {
        var lightness: Double
        var a: Double
        var b: Double

        init(red: Double, green: Double, blue: Double) {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let r = linear(red), g = linear(green), b = linear(blue)
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        }

        init(lightness: Double, a: Double, b: Double) {
            self.lightness = lightness
            self.a = a
            self.b = b
        }

        func color(lightnessOffset: Double, chromaScale: Double) -> CGColor {
            let lightness = lightness + lightnessOffset
            var scale = chromaScale
            // Reduce chroma at the same hue until the color fits sRGB; avoid channel clipping.
            for _ in 0..<16 {
                let a = a * scale, b = b * scale
                let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
                let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
                let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
                let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
                let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
                let blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
                if [r, g, blue].allSatisfy({ (0...1).contains($0) }) {
                    func encoded(_ value: Double) -> CGFloat {
                        CGFloat(value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055)
                    }
                    return CGColor(red: encoded(r), green: encoded(g), blue: encoded(blue), alpha: 1)
                }
                scale *= 0.8
            }
            let gray = CGFloat(1.055 * pow(pow(lightness, 3), 1 / 2.4) - 0.055)
            return CGColor(red: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    private static func adaptivePalette(in image: CGImage) -> LabColor {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return LabColor(lightness: 0.85, a: 0, b: 0) }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        struct HueGroup {
            var weight = 0.0
            var area = 0.0
            var a = 0.0
            var b = 0.0
        }
        let count = 24
        var groups = [HueGroup](repeating: HueGroup(), count: count)
        var lightness = 0.0
        var visibleArea = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha >= 0.1 else { continue }
            let color = LabColor(
                red: min(1, Double(pixels[index]) / 255 / alpha),
                green: min(1, Double(pixels[index + 1]) / 255 / alpha),
                blue: min(1, Double(pixels[index + 2]) / 255 / alpha)
            )
            lightness += color.lightness * alpha
            visibleArea += alpha
            let chroma = hypot(color.a, color.b)
            // Neutral text and backgrounds determine brightness, but not accent hue.
            guard chroma >= 0.025, (0.12...0.96).contains(color.lightness) else { continue }
            let hue = atan2(color.b, color.a)
            let bin = Int((hue + .pi) / (2 * .pi) * Double(count)) % count
            let weight = alpha * (0.35 + min(chroma, 0.2) * 2)
            groups[bin].weight += weight
            groups[bin].area += alpha
            groups[bin].a += color.a * weight
            groups[bin].b += color.b * weight
        }

        let averageLightness = visibleArea > 0 ? lightness / visibleArea : 0.9
        let t = min(1, max(0, (averageLightness - 0.4) / 0.4))
        let backgroundLightness = 0.32 + 0.54 * t * t * (3 - 2 * t)
        var best = HueGroup()
        // Include adjacent hue bins so colors near a bin boundary stay together.
        for index in 0..<count {
            var candidate = HueGroup()
            for offset in -1...1 {
                let group = groups[(index + offset + count) % count]
                let influence = offset == 0 ? 1.0 : 0.5
                candidate.weight += group.weight * influence
                candidate.area += group.area
                candidate.a += group.a * influence
                candidate.b += group.b * influence
            }
            // Tiny status icons must not tint an otherwise neutral screenshot.
            if candidate.area >= visibleArea * 0.015, candidate.weight > best.weight {
                best = candidate
            }
        }
        guard best.weight > 0 else {
            return LabColor(lightness: backgroundLightness, a: 0, b: 0)
        }
        let a = best.a / best.weight, b = best.b / best.weight
        let chroma = hypot(a, b)
        let targetChroma = min(0.075, chroma * 0.55)
        let scale = targetChroma / max(chroma, 0.0001)
        return LabColor(lightness: backgroundLightness, a: a * scale, b: b * scale)
    }
}
