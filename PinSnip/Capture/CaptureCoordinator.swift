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
    private var overlay: SelectionOverlayController?
    private var captureSessionState = CaptureSessionState()
    private var captureTask: Task<Void, Never>?
    private var captureTimeoutTask: Task<Void, Never>?
    private var isPreparingGIFRecording = false
    private var lastCaptureRegion: LastCaptureRegion?
    private var gifRecorder: ScreenGIFRecorder?
    private var gifRecordingPanel: GIFRecordingPanelController?
    private var isPreparingScrollingCapture = false
    private var scrollingCapture: ScreenScrollingCapture?
    private var scrollingCapturePanel: ScrollingCapturePanelController?
    private var captureHistory = CaptureHistory<Data>(limit: 10)
    private var historyPasteboardChangeCount: Int?

    init(
        pinManager: PinWindowManager,
        permissionGate: ScreenCapturePermissionGate = ScreenCapturePermissionGate(
            provider: SystemScreenCapturePermissionProvider()
        )
    ) {
        self.pinManager = pinManager
        self.permissionGate = permissionGate
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
        let captureService = captureService
        captureTask = Task { [weak self] in
            do {
                let image = try await captureService.capture(screen)
                guard let self, self.captureSessionState.isCurrent(sessionID) else { return }
                self.captureTimeoutTask?.cancel()
                self.captureTimeoutTask = nil
                self.captureTask = nil
                self.presentOverlay(
                    screen: screen,
                    screenshot: image,
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
        restoring region: LastCaptureRegion?,
        purpose: CaptureOverlayPurpose
    ) {
        let candidates = visualRegionDetector.candidates(
            in: screenshot,
            viewSize: screen.frame.size
        ) + windowDetector.candidates(on: screen)
        let mouseLocation = NSEvent.mouseLocation
        let initialPointer = CGPoint(
            x: mouseLocation.x - screen.frame.minX,
            y: mouseLocation.y - screen.frame.minY
        )
        let initialSelectionRect = region?.rect(in: screen.frame.size) ?? .zero
        let controller = SelectionOverlayController(
            screen: screen,
            screenshot: screenshot,
            windowCandidates: candidates,
            initialPointer: initialPointer,
            initialSelectionRect: initialSelectionRect,
            purpose: purpose,
            onResult: { [weak self] image, selectionRect, action in
                self?.complete(
                    image: image,
                    selectionRect: selectionRect,
                    screen: screen,
                    action: action
                )
            },
            onCancel: { [weak self] in self?.cancel() }
        )
        overlay = controller
        controller.present()
    }

    private func complete(
        image: CGImage,
        selectionRect: CGRect,
        screen: NSScreen,
        action: CaptureResultAction
    ) {
        lastCaptureRegion = LastCaptureRegion(
            rect: selectionRect,
            screenSize: screen.frame.size
        )
        if case .recordGIF = action {
            dismissOverlay()
            beginGIFRecording(screen: screen, selectionRect: selectionRect)
            return
        }
        if case .scrollCapture = action {
            dismissOverlay()
            beginScrollingCapture(screen: screen, selectionRect: selectionRect)
            return
        }
        dismissOverlay()
        switch action {
        case .copy: CaptureOutputService.copy(image)
        case .save: CaptureOutputService.save(image)
        case .pin: pinManager.pin(image)
        case .recordGIF: break
        case .scrollCapture: break
        }
        rememberCapturedScreenshot(image)
    }

    private func beginGIFRecording(screen: NSScreen, selectionRect: CGRect) {
        isPreparingGIFRecording = true
        let recorder = ScreenGIFRecorder()
        gifRecorder = recorder
        Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                try await recorder.start(
                    screen: screen,
                    selectionRect: selectionRect,
                    onStopRequested: { [weak self] in
                        self?.stopGIFRecording(action: .copy)
                    }
                )
                isPreparingGIFRecording = false
                let panel = GIFRecordingPanelController(
                    screen: screen,
                    selectionRect: selectionRect
                )
                panel.onStop = { [weak self] action in
                    self?.stopGIFRecording(action: action)
                }
                gifRecordingPanel = panel
                panel.present()
            } catch {
                recorder.cancel()
                gifRecorder = nil
                isPreparingGIFRecording = false
                presentCaptureError(error)
            }
        }
    }

    private func stopGIFRecording(action: GIFRecordingOutputAction) {
        guard let recorder = gifRecorder else { return }
        let completionPlan = GIFRecordingCompletionPlan(action: action)
        gifRecordingPanel?.showExporting()
        Task {
            let data = await recorder.stop()
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
        Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
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
                isPreparingScrollingCapture = false
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
            } catch {
                capture.cancel()
                scrollingCapture = nil
                isPreparingScrollingCapture = false
                presentCaptureError(error)
            }
        }
    }

    private func stopScrollingCapture(action: ScrollingCaptureOutputAction) {
        guard let capture = scrollingCapture else { return }
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
                CaptureOutputService.copyScrollingCapture(image)
            case .save:
                _ = CaptureOutputService.saveScrollingCapture(image)
            case .pin:
                pinManager.pin(image)
            }
            rememberCapturedScreenshot(image)
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
        scrollingCapture?.cancel()
        scrollingCapture = nil
        scrollingCapturePanel?.finish()
        scrollingCapturePanel = nil
        isPreparingScrollingCapture = false
    }

    private func cancel() {
        dismissOverlay()
    }

    private func dismissOverlay() {
        captureTask?.cancel()
        captureTask = nil
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
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
