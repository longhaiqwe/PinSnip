import CoreGraphics

public enum SelectionResizeHandle: CaseIterable, Equatable, Sendable {
    case northWest
    case north
    case northEast
    case east
    case southEast
    case south
    case southWest
    case west
}

public enum SelectionAdjustment {
    public static func center(
        of handle: SelectionResizeHandle,
        in rect: CGRect
    ) -> CGPoint {
        switch handle {
        case .northWest: CGPoint(x: rect.minX, y: rect.maxY)
        case .north: CGPoint(x: rect.midX, y: rect.maxY)
        case .northEast: CGPoint(x: rect.maxX, y: rect.maxY)
        case .east: CGPoint(x: rect.maxX, y: rect.midY)
        case .southEast: CGPoint(x: rect.maxX, y: rect.minY)
        case .south: CGPoint(x: rect.midX, y: rect.minY)
        case .southWest: CGPoint(x: rect.minX, y: rect.minY)
        case .west: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    public static func handle(
        at point: CGPoint,
        in rect: CGRect,
        hitRadius: CGFloat
    ) -> SelectionResizeHandle? {
        var nearest: (handle: SelectionResizeHandle, distanceSquared: CGFloat)?

        for handle in SelectionResizeHandle.allCases {
            let center = center(of: handle, in: rect)
            let dx = point.x - center.x
            let dy = point.y - center.y
            guard abs(dx) <= hitRadius, abs(dy) <= hitRadius else { continue }
            let distanceSquared = dx * dx + dy * dy
            if nearest == nil || distanceSquared < nearest!.distanceSquared {
                nearest = (handle, distanceSquared)
            }
        }

        return nearest?.handle
    }

    public static func resize(
        _ rect: CGRect,
        using handle: SelectionResizeHandle,
        to point: CGPoint,
        inside bounds: CGRect,
        minimumDimension: CGFloat
    ) -> CGRect {
        let rect = rect.standardized
        let bounds = bounds.standardized
        let x = min(max(point.x, bounds.minX), bounds.maxX)
        let y = min(max(point.y, bounds.minY), bounds.maxY)
        let minimumWidth = min(max(0, minimumDimension), bounds.width)
        let minimumHeight = min(max(0, minimumDimension), bounds.height)

        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .northWest, .west, .southWest:
            minX = min(max(bounds.minX, x), maxX - minimumWidth)
        case .northEast, .east, .southEast:
            maxX = max(minX + minimumWidth, min(bounds.maxX, x))
        case .north, .south:
            break
        }

        switch handle {
        case .northWest, .north, .northEast:
            maxY = max(minY + minimumHeight, min(bounds.maxY, y))
        case .southEast, .south, .southWest:
            minY = min(max(bounds.minY, y), maxY - minimumHeight)
        case .east, .west:
            break
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
