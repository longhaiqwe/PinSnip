public enum CaptureCursorPolicy {
    public static let staticScreenshotShowsCursor = false
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
