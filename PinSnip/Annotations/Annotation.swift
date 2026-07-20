import CoreGraphics

public enum Annotation: Equatable, Sendable {
    case rectangle(CGRect, RGBAColor, CGFloat)
    case arrow(from: CGPoint, to: CGPoint, RGBAColor, CGFloat)
    case pencil([CGPoint], RGBAColor, CGFloat)

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
        }
    }
}
