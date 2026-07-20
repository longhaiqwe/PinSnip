import AppKit
import PinSnipCore

@MainActor
final class CaptureCoordinator {
    private let captureService = ScreenCaptureService()
    private let permissionGate: ScreenCapturePermissionGate
    private let pinManager: PinWindowManager
    private var overlay: SelectionOverlayController?
    private var isCapturing = false

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
        guard !isCapturing else { return }
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
                presentOverlay(screen: screen, screenshot: image)
            } catch {
                isCapturing = false
                presentCaptureError(error)
            }
        }
    }

    private func presentOverlay(screen: NSScreen, screenshot: CGImage) {
        let controller = SelectionOverlayController(
            screen: screen,
            screenshot: screenshot,
            onResult: { [weak self] image, action in
                self?.complete(image: image, action: action)
            },
            onCancel: { [weak self] in self?.cancel() }
        )
        overlay = controller
        controller.present()
    }

    private func complete(image: CGImage, action: CaptureResultAction) {
        dismissOverlay()
        switch action {
        case .copy: CaptureOutputService.copy(image)
        case .save: CaptureOutputService.save(image)
        case .pin: pinManager.pin(image)
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
