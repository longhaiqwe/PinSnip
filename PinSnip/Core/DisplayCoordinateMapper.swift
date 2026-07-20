import CoreGraphics

public struct DisplayCoordinateMapper: Equatable, Sendable {
    public let viewHeight: CGFloat
    public let pixelScale: CGFloat

    public init(viewHeight: CGFloat, pixelScale: CGFloat) {
        self.viewHeight = viewHeight
        self.pixelScale = pixelScale
    }

    public func pixelRect(for pointRect: CGRect) -> CGRect {
        let minX = floor(pointRect.minX * pixelScale)
        let maxX = ceil(pointRect.maxX * pixelScale)
        let minY = floor((viewHeight - pointRect.maxY) * pixelScale)
        let maxY = ceil((viewHeight - pointRect.minY) * pixelScale)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
