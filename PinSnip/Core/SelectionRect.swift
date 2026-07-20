import CoreGraphics

public struct SelectionRect: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }

    public var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public var isEmpty: Bool {
        rect.width == 0 || rect.height == 0
    }

    public func clamped(to bounds: CGRect) -> SelectionRect {
        let intersection = rect.intersection(bounds)
        guard !intersection.isNull else {
            return SelectionRect(start: bounds.origin, end: bounds.origin)
        }
        return SelectionRect(
            start: intersection.origin,
            end: CGPoint(x: intersection.maxX, y: intersection.maxY)
        )
    }
}
