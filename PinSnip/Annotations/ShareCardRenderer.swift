import CoreGraphics
import CoreImage
import Foundation

public enum ShareCardRenderer {
    private struct RGBColor {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    public static func render(baseImage: CGImage) -> CGImage? {
        let padding = canvasPadding(for: baseImage)
        let canvasWidth = baseImage.width + padding * 2
        let canvasHeight = baseImage.height + padding * 2
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        drawBackground(baseImage, in: canvas, padding: CGFloat(padding), context: context)
        drawScreenshot(
            baseImage,
            in: canvas.insetBy(dx: CGFloat(padding), dy: CGFloat(padding)),
            context: context
        )
        return context.makeImage()
    }

    private static func canvasPadding(for image: CGImage) -> Int {
        let proportional = Int((CGFloat(min(image.width, image.height)) * 0.1).rounded())
        return min(120, max(24, proportional))
    }

    private static func drawBackground(
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
            cgColor(mix(accent, with: RGBColor(red: 0.10, green: 0.13, blue: 0.22), amount: 0.28), alpha: 0.48),
            cgColor(mix(accent, with: RGBColor(red: 0.82, green: 0.78, blue: 0.88), amount: 0.22), alpha: 0.34)
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

    private static func mix(_ color: RGBColor, with other: RGBColor, amount: CGFloat) -> RGBColor {
        RGBColor(
            red: color.red + (other.red - color.red) * amount,
            green: color.green + (other.green - color.green) * amount,
            blue: color.blue + (other.blue - color.blue) * amount
        )
    }

    private static func cgColor(_ color: RGBColor, alpha: CGFloat) -> CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [color.red, color.green, color.blue, alpha]
        )!
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

    private static func drawScreenshot(
        _ image: CGImage,
        in rect: CGRect,
        context: CGContext
    ) {
        let radius = min(32, max(12, min(rect.width, rect.height) * 0.025))
        let cardPath = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -max(2, radius * 0.15)),
            blur: max(18, radius * 1.5),
            color: CGColor(gray: 0, alpha: 0.16)
        )
        context.addPath(cardPath)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

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
}
