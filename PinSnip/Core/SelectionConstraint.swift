import CoreGraphics

public struct SelectionConstraint: Equatable, Sendable {
    public let aspectRatio: CGFloat

    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
    }

    public func rect(from start: CGPoint, to end: CGPoint, inside bounds: CGRect) -> CGRect {
        let width = abs(end.x - start.x)
        let horizontalDirection: CGFloat = end.x < start.x ? -1 : 1
        let verticalDirection: CGFloat = end.y < start.y ? -1 : 1
        let constrainedEnd = CGPoint(
            x: start.x + width * horizontalDirection,
            y: start.y + width / aspectRatio * verticalDirection
        )

        return SelectionRect(start: start, end: constrainedEnd).clamped(to: bounds).rect
    }
}
