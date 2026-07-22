import AppKit
import PinSnipCore

@MainActor
final class CaptureCoordinator {
    private let captureService = ScreenCaptureService()
    private let windowDetector = WindowDetector()
    private let permissionGate: ScreenCapturePermissionGate
    private let pinManager: PinWindowManager
    private var overlay: SelectionOverlayController?
    private var isCapturing = false
    private var isPreparingGIFRecording = false
    private var lastCaptureRegion: LastCaptureRegion?
    private var gifRecorder: ScreenGIFRecorder?
    private var gifRecordingPanel: GIFRecordingPanelController?

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
        guard !isCapturing, !isPreparingGIFRecording, gifRecorder == nil else { return }
        guard permissionGate.ensureAuthorized() else {
            presentScreenCapturePermissionRequired()
            return
        }
        guard let screen = screen(at: NSEvent.mouseLocation) else {
            NSSound.beep()
            return
        }
        isCapturing = true
        Task {
            do {
                let image = try await captureService.capture(screen)
                presentOverlay(
                    screen: screen,
                    screenshot: image,
                    restoring: region,
                    purpose: purpose
                )
            } catch {
                isCapturing = false
                presentCaptureError(error)
            }
        }
    }

    private func presentOverlay(
        screen: NSScreen,
        screenshot: CGImage,
        restoring region: LastCaptureRegion?,
        purpose: CaptureOverlayPurpose
    ) {
        let candidates = windowDetector.candidates(on: screen)
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
        dismissOverlay()
        switch action {
        case .copy: CaptureOutputService.copy(image)
        case .save: CaptureOutputService.save(image)
        case .pin: pinManager.pin(image)
        case .recordGIF: break
        }
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
                    onStopRequested: { [weak self] in self?.stopGIFRecording() }
                )
                isPreparingGIFRecording = false
                let panel = GIFRecordingPanelController(
                    screen: screen,
                    selectionRect: selectionRect
                )
                panel.onStop = { [weak self] in self?.stopGIFRecording() }
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

    private func stopGIFRecording() {
        guard let recorder = gifRecorder else { return }
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
            CaptureOutputService.copyGIF(data)
            _ = CaptureOutputService.saveGIF(data)
            if let animation = AnimatedImage(data: data) {
                pinManager.pin(animation)
            }
        }
    }

    private func cancel() {
        dismissOverlay()
    }

    private func dismissOverlay() {
        overlay?.close()
        overlay = nil
        isCapturing = false
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
