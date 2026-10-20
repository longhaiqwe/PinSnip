import AppKit
import PinSnipCore
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case displayUnavailable
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "找不到可截取的显示器。"
        case .windowUnavailable:
            return "找不到可截取的窗口。"
        }
    }
}

final class SystemScreenCapturePermissionProvider: ScreenCapturePermissionProviding {
    var isAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAuthorization() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

@MainActor
final class ScreenCaptureService {
    func capture(_ screen: NSScreen) async throws -> CGImage {
        try await captureOperation(for: screen)()
    }

    /// Read AppKit display properties on the main actor, then allow capture to run
    /// independently of AppKit's nested menu event loop.
    func captureOperation(for screen: NSScreen) -> @Sendable () async throws -> CGImage {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return {
            try await Self.capture(frame: frame, scale: scale, displayID: displayID)
        }
    }

    nonisolated private static func capture(frame: CGRect, scale: CGFloat, displayID: CGDirectDisplayID?) async throws -> CGImage {
        let supportsConfiguredRectangleCapture: Bool
        if #available(macOS 26.0, *) {
            supportsConfiguredRectangleCapture = true
        } else {
            supportsConfiguredRectangleCapture = false
        }

        switch CapturePerformancePolicy.captureRoute(
            supportsConfiguredRectangleCapture: supportsConfiguredRectangleCapture
        ) {
        case .configuredRectangle:
            if #available(macOS 26.0, *) {
                return try await captureConfiguredRectangle(frame: frame, scale: scale)
            }
            return try await captureFilteredDisplay(displayID: displayID, frame: frame, scale: scale)
        case .filteredDisplay:
            return try await captureFilteredDisplay(displayID: displayID, frame: frame, scale: scale)
        }
    }

    func captureWindow(id: CGWindowID, pixelScale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw ScreenCaptureError.windowUnavailable
        }

        let policy = WindowCaptureConfiguration(
            pointSize: window.frame.size,
            pixelScale: pixelScale
        )
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = policy.pixelWidth
        configuration.height = policy.pixelHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = policy.scalesToFit
        configuration.showsCursor = CaptureCursorPolicy.staticScreenshotShowsCursor
        configuration.shouldBeOpaque = policy.shouldBeOpaque
        configuration.ignoreShadowsSingleWindow = policy.ignoresShadow
        configuration.ignoreGlobalClipSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    @available(macOS 26.0, *)
    nonisolated private static func captureConfiguredRectangle(frame: CGRect, scale: CGFloat) async throws -> CGImage {
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int(frame.width * scale)
        configuration.height = Int(frame.height * scale)
        configuration.showsCursor = CaptureCursorPolicy.staticScreenshotShowsCursor
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local
        let output = try await SCScreenshotManager.captureScreenshot(
            rect: frame,
            configuration: configuration
        )
        guard let image = output.sdrImage else {
            throw ScreenCaptureError.displayUnavailable
        }
        return image
    }

    nonisolated private static func captureFilteredDisplay(displayID: CGDirectDisplayID?, frame: CGRect, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID,
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw ScreenCaptureError.displayUnavailable }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(frame.width * scale)
        configuration.height = Int(frame.height * scale)
        configuration.scalesToFit = false
        configuration.showsCursor = CaptureCursorPolicy.staticScreenshotShowsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}
