import AppKit

@MainActor
final class GIFRecordingPanelController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "● 录制中 00:00 / 00:30")
    private let stopButton = NSButton(title: "停止并生成 GIF", target: nil, action: nil)
    private let startedAt = Date()
    private var timer: Timer?
    private var stopRequested = false
    var onStop: (() -> Void)?

    init(screen: NSScreen, selectionRect: CGRect) {
        let size = NSSize(width: 270, height: 48)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        statusLabel.textColor = .systemRed
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        stopButton.target = self
        stopButton.action = #selector(requestStop)
        stopButton.bezelStyle = .rounded
        let stack = NSStackView(views: [statusLabel, stopButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 14
        stack.frame = content.bounds.insetBy(dx: 12, dy: 8)
        stack.autoresizingMask = [.width, .height]
        content.addSubview(stack)
        panel.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
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
        timer?.invalidate()
        timer = nil
        statusLabel.stringValue = "正在生成 GIF…"
        statusLabel.textColor = .labelColor
        stopButton.isEnabled = false
    }

    func finish() {
        timer?.invalidate()
        timer = nil
        close()
    }

    @objc private func requestStop() {
        guard !stopRequested else { return }
        stopRequested = true
        showExporting()
        onStop?()
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
