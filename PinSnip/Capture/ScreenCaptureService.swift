import AppKit
import PinSnipCore
import ScreenCaptureKit
import OSLog

enum ScreenCaptureError: LocalizedError {
    case displayUnavailable
    case windowUnavailable
    case permissionDenied
    case fallbackFailed

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "找不到可截取的显示器。"
        case .windowUnavailable:
            return "找不到可截取的窗口。"
        case .permissionDenied:
            return "PinSnip 没有屏幕录制权限。"
        case .fallbackFailed:
            return "备用截图方式也未能获取画面，请稍后重试。"
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
    private let recovery = CaptureRecovery<CGImage>()
    nonisolated private static let logger = Logger(subsystem: "com.longhai.pinsnip", category: "ScreenCapture")

    private var prewarmTask: Task<Void, Never>?

    func prewarm(_ screen: NSScreen) {
        guard prewarmTask == nil else { return }
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let recovery = recovery
        prewarmTask = Task.detached(priority: .utility) {
            // Never prompt for permission at launch. Warm up once, only when authorized.
            guard CGPreflightScreenCaptureAccess(), !Task.isCancelled else { return }
            await recovery.prewarm {
                try Task.checkCancellation()
                return try await Self.capture(frame: frame, scale: scale, displayID: displayID)
            }
        }
    }

    func capture(_ screen: NSScreen) async throws -> CGImage {
        try await captureOperation(for: screen)()
    }

    /// Read AppKit display properties on the main actor, then allow capture to run
    /// independently of AppKit's nested menu event loop.
    func captureOperation(for screen: NSScreen) -> @Sendable () async throws -> CGImage {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let recovery = recovery
        return {
            try Task.checkCancellation()
            guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permissionDenied }
            return try await recovery.capture(primary: {
                try Task.checkCancellation()
                return try await Self.capture(frame: frame, scale: scale, displayID: displayID)
            }, fallback: {
                guard let displayID else { throw ScreenCaptureError.displayUnavailable }
                return try await Self.captureFallbackDisplay(displayID)
            }, shouldFallback: { !Self.isPermissionError($0) && !($0 is CancellationError) })
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
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permissionDenied }
        return try await recovery.capture(primary: {
            try Task.checkCancellation()
            return try await Self.captureWindowUsingScreenCaptureKit(id: id, pixelScale: pixelScale)
        }, fallback: {
            try await Self.captureFallbackWindow(id)
        }, shouldFallback: { !Self.isPermissionError($0) && !($0 is CancellationError) })
    }

    nonisolated private static func captureWindowUsingScreenCaptureKit(id: CGWindowID, pixelScale: CGFloat) async throws -> CGImage {
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

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        if case ScreenCaptureError.permissionDenied = error { return true }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    nonisolated static func captureFallbackDisplay(_ displayID: CGDirectDisplayID) async throws -> CGImage {
        logger.notice("Using Quartz display recovery for display \(displayID)")
        return try await captureQuartz { PinSnipCopyDisplayImage(displayID) }
    }

    nonisolated private static func captureFallbackWindow(_ windowID: CGWindowID) async throws -> CGImage {
        logger.notice("Using Quartz window recovery for window \(windowID)")
        return try await captureQuartz { PinSnipCopyWindowImage(windowID) }
    }

    nonisolated private static func captureQuartz(_ operation: @escaping @Sendable () -> CGImage?) async throws -> CGImage {
        try Task.checkCancellation()
        // Quartz is synchronous. Never block the main actor or Swift's
        // cooperative executor while waiting on WindowServer.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard CGPreflightScreenCaptureAccess() else {
                    continuation.resume(throwing: ScreenCaptureError.permissionDenied)
                    return
                }
                guard let image = operation() else {
                    continuation.resume(throwing: ScreenCaptureError.fallbackFailed)
                    return
                }
                continuation.resume(returning: image)
            }
        }
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
