import AppKit
import ImageIO
import PinSnipCore
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class ScreenGIFRecorder {
    static let framesPerSecond = 10.0
    static let maximumDuration: TimeInterval = 30
    static let maximumPixelDimension: CGFloat = 1_200

    private struct CapturedFrame {
        let pngData: Data
        let timestamp: TimeInterval
    }

    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var capturedFrames: [CapturedFrame] = []
    private var captureTask: Task<Void, Never>?
    private var startedAt: TimeInterval?
    private var onStopRequested: (() -> Void)?

    func start(
        screen: NSScreen,
        selectionRect: CGRect,
        onStopRequested: @escaping () -> Void
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw ScreenCaptureError.displayUnavailable }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let geometry = ScreenRecordingGeometry(
            screenSize: screen.frame.size,
            selectionRect: selectionRect,
            backingScale: screen.backingScaleFactor,
            maximumPixelDimension: Self.maximumPixelDimension
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = Int(geometry.outputPixelSize.width)
        configuration.height = Int(geometry.outputPixelSize.height)
        configuration.scalesToFit = true
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        self.filter = filter
        self.configuration = configuration
        self.onStopRequested = onStopRequested
        capturedFrames.removeAll(keepingCapacity: true)
        let start = Date.timeIntervalSinceReferenceDate
        startedAt = start
        try await captureFrame(at: start)

        captureTask = Task { @MainActor [weak self] in
            await self?.captureLoop()
        }
    }

    func stop() async -> Data? {
        let task = captureTask
        captureTask = nil
        task?.cancel()
        await task?.value

        if capturedFrames.count == 1, let first = capturedFrames.first {
            capturedFrames.append(
                CapturedFrame(
                    pngData: first.pngData,
                    timestamp: first.timestamp + 1 / Self.framesPerSecond
                )
            )
        }
        let timestamps = capturedFrames.map(\.timestamp)
        let durations = GIFFrameTimeline.durations(
            for: timestamps,
            fallbackDuration: 1 / Self.framesPerSecond
        )
        let frames = capturedFrames
        let data = AnimatedGIFEncoder.encode(frameCount: frames.count) { index in
            guard let source = CGImageSourceCreateWithData(frames[index].pngData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return AnimatedImage.Frame(image: image, duration: durations[index])
        }
        reset()
        return data
    }

    func cancel() {
        captureTask?.cancel()
        reset()
    }

    private func captureLoop() async {
        let interval = 1 / Self.framesPerSecond
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let startedAt else { return }
            let timestamp = Date.timeIntervalSinceReferenceDate
            if timestamp - startedAt >= Self.maximumDuration {
                onStopRequested?()
                return
            }
            do {
                try await captureFrame(at: timestamp)
            } catch {
                onStopRequested?()
                return
            }
        }
    }

    private func captureFrame(at timestamp: TimeInterval) async throws {
        guard let filter, let configuration else { return }
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let pngData = Self.pngData(for: image) else { return }
        capturedFrames.append(CapturedFrame(pngData: pngData, timestamp: timestamp))
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func reset() {
        captureTask = nil
        filter = nil
        configuration = nil
        capturedFrames.removeAll()
        startedAt = nil
        onStopRequested = nil
    }
}
