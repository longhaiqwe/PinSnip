import AppKit
import PinSnipCore

@MainActor
final class GIFRecordingPanelController: NSWindowController {
    private let statusLabel: NSTextField
    private let saveButton: NSButton
    private let copyButton: NSButton
    private let borderController: GIFRecordingBorderController
    private let startedAt = Date()
    private var timer: Timer?
    private var stopRequested = false
    var onStop: ((GIFRecordingOutputAction) -> Void)?

    init(screen: NSScreen, selectionRect: CGRect) {
        let statusLabel = NSTextField(labelWithString: "● 录制中 00:00 / 00:30")
        statusLabel.textColor = .systemRed
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let saveButton = NSButton(title: "停止并保存…", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        let copyButton = NSButton(title: "停止并复制", target: nil, action: nil)
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        self.statusLabel = statusLabel
        self.saveButton = saveButton
        self.copyButton = copyButton
        borderController = GIFRecordingBorderController(
            screen: screen,
            selectionRect: selectionRect
        )

        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 14
        let width = GIFRecordingPanelLayout.minimumContentWidth(
            statusWidth: statusLabel.intrinsicContentSize.width,
            outputButtonWidths: [
                saveButton.intrinsicContentSize.width,
                copyButton.intrinsicContentSize.width
            ],
            spacing: spacing,
            horizontalPadding: horizontalPadding
        )
        let size = NSSize(width: width, height: 48)
        let globalSelection = selectionRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        var origin = NSPoint(
            x: min(max(screen.visibleFrame.minX, globalSelection.minX), screen.visibleFrame.maxX - size.width),
            y: globalSelection.maxY + 10
        )
        if origin.y + size.height > screen.visibleFrame.maxY {
            origin.y = max(screen.visibleFrame.minY, globalSelection.minY - size.height - 10)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "PinSnip 动图录制"
        panel.level = .floating
        panel.hidesOnDeactivate = GIFRecordingPanelLayout.hidesOnDeactivate
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        saveButton.target = self
        saveButton.action = #selector(requestSave)
        copyButton.target = self
        copyButton.action = #selector(requestCopy)
        let stack = NSStackView(views: [statusLabel, saveButton, copyButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = spacing
        stack.frame = content.bounds.insetBy(dx: horizontalPadding, dy: 8)
        stack.autoresizingMask = [.width, .height]
        content.addSubview(stack)
        panel.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        borderController.present()
        showWindow(nil)
        window?.orderFrontRegardless()
        let timer = Timer(
            timeInterval: 0.2,
            target: self,
            selector: #selector(updateElapsedTime),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func showExporting() {
        borderController.dismiss()
        timer?.invalidate()
        timer = nil
        statusLabel.stringValue = "正在生成 GIF…"
        statusLabel.textColor = .labelColor
        saveButton.isEnabled = false
        copyButton.isEnabled = false
    }

    func finish() {
        borderController.dismiss()
        timer?.invalidate()
        timer = nil
        close()
    }

    @objc private func requestSave() {
        requestStop(action: .save)
    }

    @objc private func requestCopy() {
        requestStop(action: .copy)
    }

    private func requestStop(action: GIFRecordingOutputAction) {
        guard !stopRequested else { return }
        stopRequested = true
        showExporting()
        onStop?(action)
    }

    @objc private func updateElapsedTime() {
        let seconds = min(
            Int(Date().timeIntervalSince(startedAt)),
            Int(ScreenGIFRecorder.maximumDuration)
        )
        statusLabel.stringValue = String(
            format: "● 录制中 00:%02d / 00:%02d",
            seconds,
            Int(ScreenGIFRecorder.maximumDuration)
        )
    }
}
