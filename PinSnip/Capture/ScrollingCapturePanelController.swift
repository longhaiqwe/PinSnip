import AppKit

@MainActor
final class ScrollingCapturePanelController: NSWindowController {
    private let mode: ScrollingCaptureMode
    private let statusLabel: NSTextField
    private let cancelButton: NSButton
    private let saveButton: NSButton
    private let pinButton: NSButton
    private let copyButton: NSButton
    private let borderController: GIFRecordingBorderController
    private var stopRequested = false

    var onCancel: (() -> Void)?
    var onStop: ((ScrollingCaptureOutputAction) -> Void)?

    init(
        screen: NSScreen,
        selectionRect: CGRect,
        mode: ScrollingCaptureMode
    ) {
        self.mode = mode
        statusLabel = NSTextField(
            labelWithString: mode == .automatic
                ? "自动滚动中 · 已拼接 1 屏"
                : "请在蓝框内滚动页面 · 已拼接 1 屏"
        )
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .labelColor
        cancelButton = NSButton(title: "取消", target: nil, action: nil)
        saveButton = NSButton(title: "保存…", target: nil, action: nil)
        pinButton = NSButton(title: "贴图", target: nil, action: nil)
        copyButton = NSButton(title: "完成并复制", target: nil, action: nil)
        copyButton.keyEquivalent = "\r"
        borderController = GIFRecordingBorderController(
            screen: screen,
            selectionRect: selectionRect
        )

        let buttons = [cancelButton, saveButton, pinButton, copyButton]
        buttons.forEach { $0.bezelStyle = .rounded }
        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 10
        let contentWidth = ceil(
            statusLabel.intrinsicContentSize.width
                + buttons.reduce(0) { $0 + $1.intrinsicContentSize.width }
                + spacing * CGFloat(buttons.count)
                + horizontalPadding * 2
        )
        let size = NSSize(width: max(560, contentWidth), height: 48)
        let globalSelection = selectionRect.offsetBy(
            dx: screen.frame.minX,
            dy: screen.frame.minY
        )
        var origin = NSPoint(
            x: min(
                max(screen.visibleFrame.minX, globalSelection.minX),
                screen.visibleFrame.maxX - size.width
            ),
            y: globalSelection.maxY + 10
        )
        if origin.y + size.height > screen.visibleFrame.maxY {
            origin.y = max(
                screen.visibleFrame.minY,
                globalSelection.minY - size.height - 10
            )
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "PinSnip 滚动截屏"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.target = self
        saveButton.action = #selector(save)
        pinButton.target = self
        pinButton.action = #selector(pin)
        copyButton.target = self
        copyButton.action = #selector(copyImage)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let stack = NSStackView(
            views: [statusLabel, cancelButton, saveButton, pinButton, copyButton]
        )
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
        window?.orderFrontRegardless()
    }

    func update(frameCount: Int, pixelHeight: Int) {
        let prefix = mode == .automatic ? "自动滚动中" : "请继续滚动页面"
        statusLabel.stringValue = "\(prefix) · 已拼接 \(frameCount) 屏 / \(pixelHeight) px"
    }

    func showExporting() {
        borderController.dismiss()
        statusLabel.stringValue = "正在生成长截图…"
        cancelButton.isEnabled = false
        saveButton.isEnabled = false
        pinButton.isEnabled = false
        copyButton.isEnabled = false
    }

    func finish() {
        borderController.dismiss()
        close()
    }

    @objc private func cancel() {
        guard !stopRequested else { return }
        stopRequested = true
        onCancel?()
    }

    @objc private func save() {
        requestStop(action: .save)
    }

    @objc private func pin() {
        requestStop(action: .pin)
    }

    @objc private func copyImage() {
        requestStop(action: .copy)
    }

    private func requestStop(action: ScrollingCaptureOutputAction) {
        guard !stopRequested else { return }
        stopRequested = true
        showExporting()
        onStop?(action)
    }
}
