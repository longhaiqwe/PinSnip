import CoreGraphics

public enum CaptureCursorPolicy {
    public static let staticScreenshotShowsCursor = false
}

public struct WindowCaptureConfiguration: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let shouldBeOpaque = false
    public let ignoresShadow = true
    public let scalesToFit = true

    public init(pointSize: CGSize, pixelScale: CGFloat) {
        pixelWidth = max(1, Int((pointSize.width * pixelScale).rounded()))
        pixelHeight = max(1, Int((pointSize.height * pixelScale).rounded()))
    }
}

public enum StaticScreenshotCaptureRoute: Equatable, Sendable {
    case configuredRectangle
    case filteredDisplay
}

public enum CapturePerformancePolicy {
    public static let maximumScreenshotAttempts = 1

    public static func captureRoute(
        supportsConfiguredRectangleCapture: Bool
    ) -> StaticScreenshotCaptureRoute {
        supportsConfiguredRectangleCapture ? .configuredRectangle : .filteredDisplay
    }
}
