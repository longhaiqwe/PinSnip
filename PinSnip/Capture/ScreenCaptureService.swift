import AppKit
import PinSnipCore
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case displayUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "找不到可截取的显示器。"
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
                return try await captureConfiguredRectangle(screen)
            }
            return try await captureFilteredDisplay(screen)
        case .filteredDisplay:
            return try await captureFilteredDisplay(screen)
        }
    }

    @available(macOS 26.0, *)
    private func captureConfiguredRectangle(_ screen: NSScreen) async throws -> CGImage {
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
        configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
        configuration.showsCursor = CaptureCursorPolicy.staticScreenshotShowsCursor
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local
        let output = try await SCScreenshotManager.captureScreenshot(
            rect: screen.frame,
            configuration: configuration
        )
        guard let image = output.sdrImage else {
            throw ScreenCaptureError.displayUnavailable
        }
        return image
    }

    private func captureFilteredDisplay(_ screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw ScreenCaptureError.displayUnavailable }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
        configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
        configuration.scalesToFit = false
        configuration.showsCursor = CaptureCursorPolicy.staticScreenshotShowsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}
