import AppKit
import PinSnipCore
import ScreenCaptureKit

enum ScrollingCaptureMode: Equatable {
    case automatic
    case manual
}

enum ScrollingCaptureOutputAction {
    case copy
    case save
    case pin
}

@MainActor
final class ScreenScrollingCapture {
    static let maximumPixelCount = 24_000_000

    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var assembler: ScrollingCaptureAssembler?
    private var captureTask: Task<Void, Never>?
    private var onProgress: ((Int, Int) -> Void)?
    private var onStopRequested: (() -> Void)?
    private var onAlignmentLost: (() -> Void)?
    private var onManualScrollingRequired: (() -> Void)?
    private var frameCount = 0
    private var scrollLocation = CGPoint.zero
    private var scrollStep = 0

    func start(
        screen: NSScreen,
        selectionRect: CGRect,
        mode: ScrollingCaptureMode,
        onProgress: @escaping (Int, Int) -> Void,
        onStopRequested: @escaping () -> Void,
        onAlignmentLost: @escaping () -> Void = {},
        onManualScrollingRequired: @escaping () -> Void = {}
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
        guard ScrollingCaptureExclusionPolicy.canStartCapture(
            ownApplicationCount: ownApplications.count
        ) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let geometry = ScreenRecordingGeometry(
            screenSize: screen.frame.size,
            selectionRect: selectionRect,
            backingScale: screen.backingScaleFactor,
            maximumPixelDimension: .greatestFiniteMagnitude
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRect
        configuration.width = Int(geometry.outputPixelSize.width)
        configuration.height = Int(geometry.outputPixelSize.height)
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let globalSelection = selectionRect.offsetBy(
            dx: screen.frame.minX,
            dy: screen.frame.minY
        )
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        scrollLocation = CGPoint(
            x: globalSelection.midX,
            y: primaryScreenMaxY - globalSelection.midY
        )
        scrollStep = ScrollingCaptureScrollPlan.step(selectionHeight: selectionRect.height)
        self.filter = filter
        self.configuration = configuration
        self.onProgress = onProgress
        self.onStopRequested = onStopRequested
        self.onAlignmentLost = onAlignmentLost
        self.onManualScrollingRequired = onManualScrollingRequired
        let assembler = ScrollingCaptureAssembler(
            maximumPixelCount: Self.maximumPixelCount
        )
        self.assembler = assembler

        let firstImage = try await captureFrame()
        let firstResult = assembler.append(firstImage)
        guard case let .started(totalPixelHeight) = firstResult else {
            throw ScreenCaptureError.displayUnavailable
        }
        frameCount = 1
        onProgress(frameCount, totalPixelHeight)

        captureTask = Task { @MainActor [weak self] in
            await self?.captureLoop(mode: mode)
        }
    }

    func stop() async -> CGImage? {
        let task = captureTask
        captureTask = nil
        task?.cancel()
        await task?.value
        let image = assembler?.makeImage()
        reset()
        return image
    }

    func cancel() {
        captureTask?.cancel()
        reset()
    }

    private func captureLoop(mode: ScrollingCaptureMode) async {
        switch mode {
        case .automatic:
            await automaticCaptureLoop()
        case .manual:
            await manualCaptureLoop()
        }
    }

    private func automaticCaptureLoop() async {
        try? await Task.sleep(for: .milliseconds(220))
        var progress = ScrollingCaptureAutomaticProgress()
        var shouldScroll = true
        while !Task.isCancelled {
            let didScroll = shouldScroll
            if didScroll { await postScroll(distance: scrollStep) }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }

            var didRecover = false
            var result = await captureAndAppend(retryUnmatched: true)
            // Never keep scrolling past an unmatched frame. Back up in smaller steps
            // to recover overlap with the last accepted frame before moving forward.
            if didScroll, case .unmatched = result {
                for _ in 0..<3 {
                    guard !Task.isCancelled, scrollStep > 1 else { break }
                    didRecover = true
                    let correction = max(1, scrollStep / 2)
                    scrollStep -= correction
                    await postScroll(distance: -correction)
                    try? await Task.sleep(for: .milliseconds(480))
                    guard !Task.isCancelled else { return }
                    result = await captureAndAppend(retryUnmatched: true)
                    if case .unmatched = result { continue }
                    break
                }
            }
            if let result, progress.observe(
                result,
                isForwardAttempt: didScroll && !didRecover
            ) {
                onManualScrollingRequired?()
                await manualCaptureLoop()
                return
            }
            switch result {
            case .appended:
                shouldScroll = true
            case let .unchanged(totalPixelHeight):
                if !didScroll || didRecover {
                    // The user returned to the last accepted position; resume safely.
                    shouldScroll = true
                    onProgress?(frameCount, totalPixelHeight)
                }

            case .reachedLimit:
                onStopRequested?()
                return
            case .unmatched:
                if didScroll { onAlignmentLost?() }
                shouldScroll = false
            case nil:
                return
            case .started:
                break
            }
        }
    }

    private func manualCaptureLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            let result = await captureAndAppend(retryUnmatched: false)
            if case .reachedLimit = result {
                onStopRequested?()
                return
            }
            if case .unmatched = result { onAlignmentLost?() }
            if result == nil { return }
        }
    }

    private func captureAndAppend(
        retryUnmatched: Bool
    ) async -> ScrollingCaptureAppendResult? {
        do {
            let result = assembler?.append(try await captureFrame())
            if case .unmatched = result, retryUnmatched {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return result }
                return report(assembler?.append(try await captureFrame()))
            }
            return report(result)
        } catch {
            onStopRequested?()
            return nil
        }
    }

    private func report(
        _ result: ScrollingCaptureAppendResult?
    ) -> ScrollingCaptureAppendResult? {
        if case let .appended(_, totalPixelHeight) = result {
            frameCount += 1
            onProgress?(frameCount, totalPixelHeight)
        }
        return result
    }

    private func captureFrame() async throws -> CGImage {
        guard let filter, let configuration else {
            throw ScreenCaptureError.displayUnavailable
        }
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func postScroll(distance: Int) async {
        for pulse in ScrollingCaptureScrollPlan.pulses(distance: distance) {
            guard !Task.isCancelled,
                  let event = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 1,
                    wheel1: -Int32(pulse),
                    wheel2: 0,
                    wheel3: 0
                  )
            else { return }
            event.location = scrollLocation
            event.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(18))
        }
    }

    private func reset() {
        captureTask = nil
        filter = nil
        configuration = nil
        assembler = nil
        onProgress = nil
        onStopRequested = nil
        onAlignmentLost = nil
        onManualScrollingRequired = nil
        frameCount = 0
        scrollLocation = .zero
        scrollStep = 0
    }
}
