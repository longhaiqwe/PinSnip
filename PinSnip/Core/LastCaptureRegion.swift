import CoreGraphics

public struct LastCaptureRegion: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(rect: CGRect, screenSize: CGSize) {
        x = rect.origin.x / screenSize.width
        y = rect.origin.y / screenSize.height
        width = rect.width / screenSize.width
        height = rect.height / screenSize.height
    }

    public func rect(in screenSize: CGSize) -> CGRect {
        CGRect(
            x: x * screenSize.width,
            y: y * screenSize.height,
            width: width * screenSize.width,
            height: height * screenSize.height
        )
    }
}
