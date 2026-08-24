import CoreGraphics

public enum Annotation: Equatable, Sendable {
    case rectangle(CGRect, RGBAColor, CGFloat)
    case arrow(from: CGPoint, to: CGPoint, RGBAColor, CGFloat)
    case pencil([CGPoint], RGBAColor, CGFloat)
    case text(rect: CGRect, text: String, color: RGBAColor, fontSize: CGFloat)
    case number(center: CGPoint, value: Int, color: RGBAColor, diameter: CGFloat)
    case mosaic(CGRect, pixelSize: CGFloat)
    case mosaicPencil([CGPoint], width: CGFloat)

    public func mapped(relativeTo origin: CGPoint, scale: CGFloat) -> Annotation {
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: (value.x - origin.x) * scale, y: (value.y - origin.y) * scale)
        }

        switch self {
        case let .rectangle(rect, color, width):
            return .rectangle(
                CGRect(
                    x: (rect.minX - origin.x) * scale,
                    y: (rect.minY - origin.y) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                ),
                color,
                width * scale
            )
        case let .arrow(from, to, color, width):
            return .arrow(from: point(from), to: point(to), color, width * scale)
        case let .pencil(points, color, width):
            return .pencil(points.map(point), color, width * scale)
        case let .text(rect, text, color, fontSize):
            return .text(
                rect: CGRect(
                    x: (rect.minX - origin.x) * scale,
                    y: (rect.minY - origin.y) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                ),
                text: text,
                color: color,
                fontSize: fontSize * scale
            )
        case let .number(center, value, color, diameter):
            return .number(
                center: point(center),
                value: value,
                color: color,
                diameter: diameter * scale
            )
        case let .mosaic(rect, pixelSize):
            return .mosaic(
                CGRect(
                    x: (rect.minX - origin.x) * scale,
                    y: (rect.minY - origin.y) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale
                ),
                pixelSize: pixelSize * scale
            )
        case let .mosaicPencil(points, width):
            return .mosaicPencil(points.map(point), width: width * scale)
        }
    }
}

public enum TextAnnotationResizeEdge: Equatable, Sendable {
    case left
    case right
}

public enum TextAnnotationHandle: CaseIterable, Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var horizontalEdge: TextAnnotationResizeEdge {
        switch self {
        case .topLeft, .bottomLeft: .left
        case .topRight, .bottomRight: .right
        }
    }
}

public enum TextAnnotationSizePreset: Int, CaseIterable, Equatable, Sendable {
    case small
    case medium
    case large

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 22
        case .large: 30
        }
    }

    public static func closest(to fontSize: CGFloat) -> TextAnnotationSizePreset {
        allCases.min { abs($0.fontSize - fontSize) < abs($1.fontSize - fontSize) } ?? .medium
    }
}

public enum TextAnnotationPalette {
    public static let colors: [RGBAColor] = [
        RGBAColor(red: 0.08, green: 0.65, blue: 0.97),
        RGBAColor(red: 0.49, green: 0.86, blue: 0),
        RGBAColor(red: 1, green: 0.72, blue: 0),
        RGBAColor(red: 0.25, green: 0.26, blue: 0.27),
        RGBAColor(red: 1, green: 1, blue: 1),
        RGBAColor(red: 1, green: 0.25, blue: 0.29)
    ]
}

public enum TextAnnotationLayout {
    public static let horizontalTextInset: CGFloat = 4
    public static let verticalTextInset: CGFloat = 2

    public static func contentRect(in rect: CGRect) -> CGRect {
        rect.insetBy(
            dx: min(horizontalTextInset, rect.width / 2),
            dy: min(verticalTextInset, rect.height / 2)
        )
    }

    public static func effectiveContentWidth(for boxWidth: CGFloat) -> CGFloat {
        max(1, boxWidth - horizontalTextInset * 2)
    }

    public static func initialRect(
        at point: CGPoint,
        inside bounds: CGRect,
        preferredWidth: CGFloat,
        minimumWidth: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let width = min(bounds.width, max(1, max(minimumWidth, preferredWidth)))
        let height = min(bounds.height, max(1, height))
        return CGRect(
            x: min(max(bounds.minX, point.x), bounds.maxX - width),
            y: min(max(bounds.minY, point.y), bounds.maxY - height),
            width: width,
            height: height
        )
    }

    public static func resize(
        _ rect: CGRect,
        handle: TextAnnotationHandle,
        to point: CGPoint,
        inside bounds: CGRect,
        minimumWidth: CGFloat
    ) -> CGRect {
        resize(
            rect,
            edge: handle.horizontalEdge,
            to: point.x,
            inside: bounds,
            minimumWidth: minimumWidth
        )
    }

    public static func resize(
        _ rect: CGRect,
        edge: TextAnnotationResizeEdge,
        to x: CGFloat,
        inside bounds: CGRect,
        minimumWidth: CGFloat
    ) -> CGRect {
        let minimumWidth = max(1, minimumWidth)
        switch edge {
        case .left:
            let maximumX = rect.maxX - minimumWidth
            let newMinX = min(max(bounds.minX, x), maximumX)
            return CGRect(
                x: newMinX,
                y: rect.minY,
                width: rect.maxX - newMinX,
                height: rect.height
            )
        case .right:
            let minimumX = rect.minX + minimumWidth
            let newMaxX = max(min(bounds.maxX, x), minimumX)
            return CGRect(
                x: rect.minX,
                y: rect.minY,
                width: newMaxX - rect.minX,
                height: rect.height
            )
        }
    }

    public static func move(
        _ rect: CGRect,
        by offset: CGSize,
        inside bounds: CGRect
    ) -> CGRect {
        let maximumX = max(bounds.minX, bounds.maxX - rect.width)
        let maximumY = max(bounds.minY, bounds.maxY - rect.height)
        return CGRect(
            x: min(max(bounds.minX, rect.minX + offset.width), maximumX),
            y: min(max(bounds.minY, rect.minY + offset.height), maximumY),
            width: rect.width,
            height: rect.height
        )
    }
}
