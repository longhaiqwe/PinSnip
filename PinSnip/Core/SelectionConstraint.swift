import CoreGraphics

public struct SelectionConstraint: Equatable, Sendable {
    public let aspectRatio: CGFloat

    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
    }

    public func rect(from start: CGPoint, to end: CGPoint, inside bounds: CGRect) -> CGRect {
        let horizontalDirection: CGFloat = end.x < start.x ? -1 : 1
        let verticalDirection: CGFloat = end.y < start.y ? -1 : 1
        let horizontalCapacity = horizontalDirection > 0
            ? bounds.maxX - start.x
            : start.x - bounds.minX
        let verticalCapacity = verticalDirection > 0
            ? bounds.maxY - start.y
            : start.y - bounds.minY
        let width = min(
            abs(end.x - start.x),
            max(0, horizontalCapacity),
            max(0, verticalCapacity) * aspectRatio
        )
        let constrainedEnd = CGPoint(
            x: start.x + width * horizontalDirection,
            y: start.y + width / aspectRatio * verticalDirection
        )

        return SelectionRect(start: start, end: constrainedEnd).rect
    }
}
