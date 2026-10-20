import CoreGraphics

public enum ArrowAnnotationStyle: Int, CaseIterable, Equatable, Sendable {
    case line, filled, hollow

    public var title: String {
        switch self {
        case .line: "线条箭头"
        case .filled: "实心箭头"
        case .hollow: "空心箭头"
        }
    }
}

public enum Annotation: Equatable, Sendable {
    case rectangle(CGRect, RGBAColor, CGFloat)
    case arrow(from: CGPoint, to: CGPoint, RGBAColor, CGFloat, style: ArrowAnnotationStyle = .line)
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
        case let .arrow(from, to, color, width, style):
            return .arrow(from: point(from), to: point(to), color, width * scale, style: style)
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

public enum RectangleAnnotationLayout {
    public static func move(
        _ annotation: Annotation,
        by offset: CGSize,
        inside bounds: CGRect
    ) -> Annotation {
        guard case let .rectangle(rect, color, lineWidth) = annotation else {
            return annotation
        }
        let maximumX = max(bounds.minX, bounds.maxX - rect.width)
        let maximumY = max(bounds.minY, bounds.maxY - rect.height)
        let movedRect = CGRect(
            x: min(max(bounds.minX, rect.minX + offset.width), maximumX),
            y: min(max(bounds.minY, rect.minY + offset.height), maximumY),
            width: rect.width,
            height: rect.height
        )
        return .rectangle(movedRect, color, lineWidth)
    }

    public static func resize(
        _ annotation: Annotation,
        using handle: SelectionResizeHandle,
        to point: CGPoint,
        inside bounds: CGRect,
        minimumDimension: CGFloat
    ) -> Annotation {
        guard case let .rectangle(rect, color, lineWidth) = annotation else {
            return annotation
        }
        return .rectangle(
            SelectionAdjustment.resize(
                rect,
                using: handle,
                to: point,
                inside: bounds,
                minimumDimension: minimumDimension
            ),
            color,
            lineWidth
        )
    }

    public static func hitTest(
        _ point: CGPoint,
        annotation: Annotation,
        tolerance: CGFloat
    ) -> Bool {
        guard case let .rectangle(rect, _, _) = annotation else { return false }
        return rect.insetBy(dx: -max(0, tolerance), dy: -max(0, tolerance)).contains(point)
    }
}

public enum TextAnnotationHandle: CaseIterable, Equatable, Sendable {
    case left
    case right

    public var horizontalEdge: TextAnnotationResizeEdge {
        switch self {
        case .left: .left
        case .right: .right
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

public enum NumberAnnotationSizePreset: Int, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        case .extraLarge: "特大"
        }
    }

    public var diameter: CGFloat {
        switch self {
        case .small: 20
        case .medium: 28
        case .large: 40
        case .extraLarge: 56
        }
    }

    public static func closest(to diameter: CGFloat) -> Self {
        allCases.min { abs($0.diameter - diameter) < abs($1.diameter - diameter) } ?? .medium
    }
}

public enum TextAnnotationPalette {
    public static let colorNames = ["蓝色", "绿色", "黄色", "深灰色", "白色", "红色"]
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
    public static let minimumWidth: CGFloat = 48
    public static let initialWidth: CGFloat = 160
    public static let maximumAutomaticWidth: CGFloat = 220
    public static let handleDiameter: CGFloat = 10
    public static let handleHitSize: CGFloat = 24
    public static let borderHitWidth: CGFloat = 8
    public static let chromeInset: CGFloat = handleHitSize / 2 + borderHitWidth
    public static let dragThreshold: CGFloat = 3

    public enum HitTarget: Equatable {
        case resize(TextAnnotationHandle)
        case move
        case text
    }

    public static func handleRect(_ handle: TextAnnotationHandle, in rect: CGRect, hitArea: Bool = false) -> CGRect {
        let size = hitArea ? handleHitSize : handleDiameter
        // Keep the resize targets outside the first/last glyph's editing area.
        let x = handle == .left ? rect.minX - borderHitWidth : rect.maxX + borderHitWidth
        return CGRect(x: x - size / 2, y: rect.midY - size / 2, width: size, height: size)
    }

    public static func hitTarget(at point: CGPoint, in rect: CGRect) -> HitTarget? {
        for handle in TextAnnotationHandle.allCases {
            if handleRect(handle, in: rect, hitArea: true).contains(point) { return .resize(handle) }
        }
        if rect.insetBy(dx: -borderHitWidth, dy: -borderHitWidth).contains(point),
           !rect.insetBy(dx: verticalTextInset, dy: verticalTextInset).contains(point) {
            return .move
        }
        return rect.contains(point) ? .text : nil
    }

    public static func hasDragged(from start: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= dragThreshold
    }

    /// Resize relative to the grab point, without snapping the edge to the pointer.
    public static func resizePoint(for handle: TextAnnotationHandle, in rect: CGRect,
                                   from start: CGPoint, to point: CGPoint) -> CGPoint {
        CGPoint(x: (handle == .left ? rect.minX : rect.maxX) + point.x - start.x, y: point.y)
    }

    /// Grow down from the existing top; at the bottom boundary shift up instead of clipping lines.
    public static func fittingHeight(_ rect: CGRect, height: CGFloat, inside bounds: CGRect) -> CGRect {
        let height = min(bounds.height, max(1, height))
        return CGRect(x: rect.minX,
                      y: min(bounds.maxY - height, max(bounds.minY, rect.maxY - height)),
                      width: rect.width, height: height)
    }

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
            x: min(max(bounds.minX, point.x - horizontalTextInset), bounds.maxX - width),
            y: min(max(bounds.minY, point.y - height / 2), bounds.maxY - height),
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
        switch edge {
        case .left:
            let minimumWidth = min(max(1, minimumWidth), rect.maxX - bounds.minX)
            let maximumX = rect.maxX - minimumWidth
            let newMinX = min(max(bounds.minX, x), maximumX)
            return CGRect(
                x: newMinX,
                y: rect.minY,
                width: rect.maxX - newMinX,
                height: rect.height
            )
        case .right:
            let minimumWidth = min(max(1, minimumWidth), bounds.maxX - rect.minX)
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
