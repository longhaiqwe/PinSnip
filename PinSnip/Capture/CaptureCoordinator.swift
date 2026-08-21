import AppKit
import PinSnipCore

enum CapturedScreenshotPasteResult {
    case pinned
    case useClipboard
    case historyExhausted
}

@MainActor
final class CaptureCoordinator {
    private static let capturePreparationTimeout: Duration = .seconds(5)

    private let captureService = ScreenCaptureService()
    private let windowDetector = WindowDetector()
    private let visualRegionDetector = VisualRegionDetector()
    private let permissionGate: ScreenCapturePermissionGate
    private let pinManager: PinWindowManager
    private var shareStyle: ShareStyle
    private var overlay: SelectionOverlayController?
    private var captureSessionState = CaptureSessionState()
    private var captureTask: Task<Void, Never>?
    private var captureTimeoutTask: Task<Void, Never>?
    private var visualDetectionTask: Task<Void, Never>?
    private var visualPrewarmTask: Task<Void, Never>?
    private var isPreparingGIFRecording = false
    private var lastCaptureRegion: LastCaptureRegion?
    private var gifRecorder: ScreenGIFRecorder?
    private var gifPreparationTask: Task<Void, Never>?
    private var gifRecordingPanel: GIFRecordingPanelController?
    private var isPreparingScrollingCapture = false
    private var scrollingCapture: ScreenScrollingCapture?
    private var scrollingPreparationTask: Task<Void, Never>?
    private var scrollingCapturePanel: ScrollingCapturePanelController?
    private var captureHistory = CaptureHistory<Data>(limit: 10)
    private var historyPasteboardChangeCount: Int?

    var onCaptureCancellationAvailabilityChanged: ((Bool) -> Void)?

    init(
        pinManager: PinWindowManager,
        shareStyle: ShareStyle = .paperCut,
        permissionGate: ScreenCapturePermissionGate = ScreenCapturePermissionGate(
            provider: SystemScreenCapturePermissionProvider()
        )
    ) {
        self.pinManager = pinManager
        self.shareStyle = shareStyle
        self.permissionGate = permissionGate
    }

    func updateShareStyle(_ style: ShareStyle) {
        shareStyle = style
    }

    func prewarmCaptureAnalysis() {
        guard visualPrewarmTask == nil else { return }
        let visualRegionDetector = visualRegionDetector
        visualPrewarmTask = Task.detached(priority: .utility) {
            visualRegionDetector.prewarm()
        }
    }

    func startCapture() {
        startCapture(restoring: nil, purpose: .stillImage)
    }

    func startGIFRecordingSelection() {
        startCapture(restoring: nil, purpose: .animatedGIF)
    }

    func startScrollingCaptureSelection() {
        startCapture(restoring: nil, purpose: .scrollingCapture)
    }

    func startLastRegionCapture() {
        guard let lastCaptureRegion else {
            NSSound.beep()
            return
        }
        startCapture(restoring: lastCaptureRegion, purpose: .stillImage)
    }

    private func startCapture(
        restoring region: LastCaptureRegion?,
        purpose: CaptureOverlayPurpose
    ) {
        guard !isPreparingGIFRecording, gifRecorder == nil,
              !isPreparingScrollingCapture, scrollingCapture == nil,
              let sessionID = captureSessionState.begin()
        else { return }
        guard permissionGate.ensureAuthorized() else {
            captureSessionState.end(sessionID)
            presentScreenCapturePermissionRequired()
            return
        }
        guard let screen = screen(at: NSEvent.mouseLocation) else {
            captureSessionState.end(sessionID)
            NSSound.beep()
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let initialPointer = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: mouseLocation.y - screen.frame.minY
        )
        let initialWindowCandidates = windowDetector.candidates(on: screen)
        let captureService = captureService
        captureTask = Task { [weak self] in
            do {
                var candidatesBefore = initialWindowCandidates
                var capturedImage: CGImage?
                var stableCandidates = [WindowCandidate]()
                var targetWasStable = false

                for attempt in 0..<CapturePerformancePolicy.maximumScreenshotAttempts {
                    let image = try await captureService.capture(screen)
                    guard let self, self.captureSessionState.isCurrent(sessionID) else {
                        return
                    }
                    let candidatesAfter = self.windowDetector.candidates(on: screen)
                    capturedImage = image
                    stableCandidates = WindowCandidate.stableCandidates(
                        before: candidatesBefore,
                        after: candidatesAfter
                    )
                    targetWasStable = !WindowCandidate.requiresRecapture(
                        at: initialPointer,
                        before: candidatesBefore,
                        after: candidatesAfter
                    )
                    if targetWasStable { break }

                    candidatesBefore = candidatesAfter
                    if attempt + 1 < CapturePerformancePolicy.maximumScreenshotAttempts {
                        await Task.yield()
                    }
                }

                guard let self, self.captureSessionState.isCurrent(sessionID),
                      let capturedImage
                else { return }
                self.captureTimeoutTask?.cancel()
                self.captureTimeoutTask = nil
                self.captureTask = nil
                self.presentOverlay(
                    screen: screen,
                    screenshot: capturedImage,
                    windowCandidates: targetWasStable ? stableCandidates : [],
                    initialPointer: initialPointer,
                    sessionID: sessionID,
                    restoring: region,
                    purpose: purpose
                )
            } catch {
                guard let self, self.captureSessionState.end(sessionID) else { return }
                self.captureTimeoutTask?.cancel()
                self.captureTimeoutTask = nil
                self.captureTask = nil
                self.presentCaptureError(error)
            }
        }
        captureTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.capturePreparationTimeout)
            } catch {
                return
            }
            guard let self, self.captureSessionState.end(sessionID) else { return }
            self.captureTask?.cancel()
            self.captureTask = nil
            self.captureTimeoutTask = nil
            self.presentCaptureTimeout()
        }
    }

    private func presentOverlay(
        screen: NSScreen,
        screenshot: CGImage,
        windowCandidates: [WindowCandidate],
        initialPointer: CGPoint,
        sessionID: UUID,
        restoring region: LastCaptureRegion?,
        purpose: CaptureOverlayPurpose
    ) {
        let initialSelectionRect = region?.rect(in: screen.frame.size) ?? .zero
        let controller = SelectionOverlayController(
            screen: screen,
            screenshot: screenshot,
            windowCandidates: windowCandidates,
            initialPointer: initialPointer,
            initialSelectionRect: initialSelectionRect,
            purpose: purpose,
            onResult: { [weak self] result in
                self?.complete(
                    result,
                    screen: screen
                )
            },
            onCancel: { [weak self] in self?.cancel() }
        )
        overlay = controller
        controller.present()
        guard region == nil else { return }
        startVisualRegionDetection(
            in: screenshot,
            viewSize: screen.frame.size,
            sessionID: sessionID
        )
    }

    private func startVisualRegionDetection(
        in screenshot: CGImage,
        viewSize: CGSize,
        sessionID: UUID
    ) {
        visualDetectionTask?.cancel()
        let visualRegionDetector = visualRegionDetector
        visualDetectionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let candidates = visualRegionDetector.candidates(
                in: screenshot,
                viewSize: viewSize
            )
            guard !Task.isCancelled else { return }
            await self?.applyVisualRegionCandidates(
                candidates,
                sessionID: sessionID
            )
        }
    }

    private func applyVisualRegionCandidates(
        _ candidates: [WindowCandidate],
        sessionID: UUID
    ) {
        guard captureSessionState.isCurrent(sessionID) else { return }
        overlay?.addWindowCandidates(candidates)
        visualDetectionTask = nil
    }

    private func complete(
        _ result: CaptureResult,
        screen: NSScreen
    ) {
        lastCaptureRegion = LastCaptureRegion(
            rect: result.selectionRect,
            screenSize: screen.frame.size
        )
        if case .recordGIF = result.action {
            dismissOverlay()
            beginGIFRecording(screen: screen, selectionRect: result.selectionRect)
            return
        }
        if case .scrollCapture = result.action {
            dismissOverlay()
            beginScrollingCapture(screen: screen, selectionRect: result.selectionRect)
            return
        }
        dismissOverlay()

        let captureService = captureService
        Task { [weak self] in
            guard let self else { return }
            var baseImage = result.image
            if let windowID = result.windowID,
               let windowImage = try? await captureService.captureWindow(
                   id: windowID,
                   pixelScale: screen.backingScaleFactor
               ),
               windowImage.width == result.image.width,
               windowImage.height == result.image.height {
                baseImage = windowImage
            }
            guard let image = AnnotationRenderer.render(
                baseImage: baseImage,
                annotations: result.annotations
            ) else {
                NSSound.beep()
                return
            }
            self.deliver(image, action: result.action)
        }
    }

    private func deliver(_ image: CGImage, action: CaptureResultAction) {
        switch action {
        case .copy:
            let copiedImage = CaptureOutputService.copy(image, style: shareStyle)
            rememberCapturedScreenshot(copiedImage)
        case .save:
            if let savedImage = CaptureOutputService.save(image, style: shareStyle) {
                rememberCapturedScreenshot(savedImage)
            }
        case .pin:
            let pinnedImage = CaptureOutputService.render(image, style: shareStyle)
            pinManager.pin(pinnedImage)
            rememberCapturedScreenshot(pinnedImage)
        case .recordGIF: break
        case .scrollCapture: break
        }
    }

    private func beginGIFRecording(screen: NSScreen, selectionRect: CGRect) {
        isPreparingGIFRecording = true
        let recorder = ScreenGIFRecorder()
        gifRecorder = recorder
        onCaptureCancellationAvailabilityChanged?(true)
        gifPreparationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled,
                      let self,
                      self.gifRecorder === recorder
                else { return }
                try await recorder.start(
                    screen: screen,
                    selectionRect: selectionRect,
                    onStopRequested: { [weak self] in
                        self?.stopGIFRecording(action: .copy)
                    }
                )
                guard !Task.isCancelled, self.gifRecorder === recorder else {
                    recorder.cancel()
                    return
                }
                self.gifPreparationTask = nil
                self.isPreparingGIFRecording = false
                let panel = GIFRecordingPanelController(
                    screen: screen,
                    selectionRect: selectionRect
                )
                panel.onCancel = { [weak self] in
                    self?.cancelGIFRecording()
                }
                panel.onStop = { [weak self] action in
                    self?.stopGIFRecording(action: action)
                }
                self.gifRecordingPanel = panel
                panel.present()
            } catch {
                guard let self, self.gifRecorder === recorder else { return }
                self.gifPreparationTask = nil
                recorder.cancel()
                self.gifRecorder = nil
                self.isPreparingGIFRecording = false
                self.onCaptureCancellationAvailabilityChanged?(false)
                if !(error is CancellationError) {
                    self.presentCaptureError(error)
                }
            }
        }
    }

    private func stopGIFRecording(action: GIFRecordingOutputAction) {
        guard let recorder = gifRecorder else { return }
        gifPreparationTask?.cancel()
        gifPreparationTask = nil
        onCaptureCancellationAvailabilityChanged?(false)
        let completionPlan = GIFRecordingCompletionPlan(action: action)
        gifRecordingPanel?.showExporting()
        Task {
            let data = await recorder.stop(style: shareStyle)
            gifRecordingPanel?.finish()
            gifRecordingPanel = nil
            gifRecorder = nil
            isPreparingGIFRecording = false

            guard let data else {
                presentGIFEncodingError()
                return
            }
            if completionPlan.copiesToClipboard {
                CaptureOutputService.copyGIF(data)
            }
            if completionPlan.presentsSavePanel {
                _ = CaptureOutputService.saveGIF(data)
            }
        }
    }

    private func beginScrollingCapture(
        screen: NSScreen,
        selectionRect: CGRect
    ) {
        isPreparingScrollingCapture = true
        let mode: ScrollingCaptureMode = AXIsProcessTrusted() ? .automatic : .manual
        let capture = ScreenScrollingCapture()
        scrollingCapture = capture
        onCaptureCancellationAvailabilityChanged?(true)
        let panel = ScrollingCapturePanelController(
            screen: screen,
            selectionRect: selectionRect,
            mode: mode
        )
        panel.onCancel = { [weak self] in
            self?.cancelScrollingCapture()
        }
        panel.onStop = { [weak self] action in
            self?.stopScrollingCapture(action: action)
        }
        scrollingCapturePanel = panel
        panel.present()

        scrollingPreparationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled,
                      let self,
                      self.scrollingCapture === capture
                else { return }
                try await capture.start(
                    screen: screen,
                    selectionRect: selectionRect,
                    mode: mode,
                    onProgress: { [weak self] frameCount, pixelHeight in
                        self?.scrollingCapturePanel?.update(
                            frameCount: frameCount,
                            pixelHeight: pixelHeight
                        )
                    },
                    onStopRequested: { [weak self] in
                        self?.stopScrollingCapture(action: .copy)
                    }
                )
                guard scrollingCapture === capture else {
                    capture.cancel()
                    return
                }
                self.scrollingPreparationTask = nil
                self.isPreparingScrollingCapture = false
            } catch {
                guard let self, self.scrollingCapture === capture else { return }
                self.scrollingPreparationTask = nil
                capture.cancel()
                self.scrollingCapture = nil
                self.scrollingCapturePanel?.finish()
                self.scrollingCapturePanel = nil
                self.isPreparingScrollingCapture = false
                self.onCaptureCancellationAvailabilityChanged?(false)
                if !(error is CancellationError) {
                    self.presentCaptureError(error)
                }
            }
        }
    }

    private func stopScrollingCapture(action: ScrollingCaptureOutputAction) {
        guard let capture = scrollingCapture else { return }
        scrollingPreparationTask?.cancel()
        scrollingPreparationTask = nil
        onCaptureCancellationAvailabilityChanged?(false)
        scrollingCapture = nil
        scrollingCapturePanel?.showExporting()
        Task {
            let image = await capture.stop()
            scrollingCapturePanel?.finish()
            scrollingCapturePanel = nil
            isPreparingScrollingCapture = false

            guard let image else {
                presentScrollingCaptureError()
                return
            }
            switch action {
            case .copy:
                let copiedImage = CaptureOutputService.copyScrollingCapture(image, style: shareStyle)
                rememberCapturedScreenshot(copiedImage)
            case .save:
                if let savedImage = CaptureOutputService.saveScrollingCapture(image, style: shareStyle) {
                    rememberCapturedScreenshot(savedImage)
                }
            case .pin:
                let pinnedImage = CaptureOutputService.render(image, style: shareStyle)
                pinManager.pin(pinnedImage)
                rememberCapturedScreenshot(pinnedImage)
            }
        }
    }

    func pinNextCapturedScreenshot(
        pasteboard: NSPasteboard = .general
    ) -> CapturedScreenshotPasteResult {
        guard !captureHistory.isEmpty else { return .useClipboard }

        if historyPasteboardChangeCount != pasteboard.changeCount {
            historyPasteboardChangeCount = pasteboard.changeCount
            return .useClipboard
        }

        while let data = captureHistory.nextForPasting() {
            guard let image = NSBitmapImageRep(data: data)?.cgImage else { continue }
            pinManager.pin(image)
            return .pinned
        }

        NSSound.beep()
        return .historyExhausted
    }

    private func rememberCapturedScreenshot(
        _ image: CGImage,
        pasteboard: NSPasteboard = .general
    ) {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return
        }
        captureHistory.record(data)
        historyPasteboardChangeCount = pasteboard.changeCount
    }

    private func cancelScrollingCapture() {
        scrollingPreparationTask?.cancel()
        scrollingPreparationTask = nil
        scrollingCapture?.cancel()
        scrollingCapture = nil
        scrollingCapturePanel?.finish()
        scrollingCapturePanel = nil
        isPreparingScrollingCapture = false
        onCaptureCancellationAvailabilityChanged?(false)
    }

    private func cancelGIFRecording() {
        gifPreparationTask?.cancel()
        gifPreparationTask = nil
        gifRecorder?.cancel()
        gifRecorder = nil
        gifRecordingPanel?.finish()
        gifRecordingPanel = nil
        isPreparingGIFRecording = false
        onCaptureCancellationAvailabilityChanged?(false)
    }

    func cancelActiveCapture() {
        if gifRecorder != nil || isPreparingGIFRecording {
            cancelGIFRecording()
            return
        }
        if scrollingCapture != nil || isPreparingScrollingCapture {
            cancelScrollingCapture()
        }
    }

    private func cancel() {
        dismissOverlay()
    }

    private func dismissOverlay() {
        captureTask?.cancel()
        captureTask = nil
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
        visualDetectionTask?.cancel()
        visualDetectionTask = nil
        captureSessionState.endCurrent()
        overlay?.close()
        overlay = nil
    }

    private func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
    }

    private func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PinSnip 无法读取屏幕"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 PinSnip，然后重试。\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if runForeground(alert) == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func presentCaptureTimeout() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "PinSnip 读取屏幕超时"
        alert.informativeText = "macOS 的屏幕捕获服务没有响应。现在可以再按一次 F1 或 F3 重试。"
        alert.addButton(withTitle: "好")
        _ = runForeground(alert)
    }

    private func presentScreenCapturePermissionRequired() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要开启屏幕录制权限"
        alert.informativeText = "macOS 需要你在系统设置中手动允许 PinSnip。开启后请退出并重新打开 PinSnip，再按截图快捷键。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if runForeground(alert) == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func presentGIFEncodingError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法生成 GIF"
        alert.informativeText = "录制帧不足或编码失败，请重新录制。"
        alert.addButton(withTitle: "好")
        _ = runForeground(alert)
    }

    private func presentScrollingCaptureError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法生成滚动截屏"
        alert.informativeText = "没有收集到可拼接的页面画面，请重新选择滚动区域后再试。"
        alert.addButton(withTitle: "好")
        _ = runForeground(alert)
    }

    private func runForeground(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return alert.runModal()
    }

    private func openScreenCaptureSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
