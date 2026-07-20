import CoreGraphics

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

        for annotation in annotations {
            draw(annotation, in: context)
        }
        return context.makeImage()
    }

    private static func draw(_ annotation: Annotation, in context: CGContext) {
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
        }
    }

    private static func configure(_ context: CGContext, color: RGBAColor, width: CGFloat) {
        context.setStrokeColor(
            CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [color.red, color.green, color.blue, color.alpha]
            )!
        )
        context.setLineWidth(max(1, width))
    }
}
