import AppKit
import PinSnipCore

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
    private var controlState = ScrollingCaptureControlState.preparing

    var onCancel: (() -> Void)?
    var onStop: ((ScrollingCaptureOutputAction) -> Void)?

    init(
        screen: NSScreen,
        selectionRect: CGRect,
        mode: ScrollingCaptureMode
    ) {
        self.mode = mode
        statusLabel = NSTextField(labelWithString: "准备滚动截屏…")
        statusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton = Self.iconButton(symbol: "xmark", help: "取消滚动截屏")
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton = Self.actionButton(
            title: "保存",
            symbol: "square.and.arrow.down",
            help: "保存分享长图…"
        )
        pinButton = Self.actionButton(
            title: "贴图",
            symbol: "pin",
            help: "贴原始长图到屏幕"
        )
        copyButton = Self.actionButton(
            title: "完成",
            symbol: "checkmark",
            help: "完成并复制分享长图"
        )
        copyButton.bezelColor = .controlAccentColor
        copyButton.contentTintColor = .white
        copyButton.keyEquivalent = "\r"
        borderController = GIFRecordingBorderController(
            screen: screen,
            selectionRect: selectionRect
        )

        let globalSelection = selectionRect.offsetBy(
            dx: screen.frame.minX,
            dy: screen.frame.minY
        )
        let panelFrame = ScrollingCapturePanelLayout.panelFrame(
            visibleFrame: screen.visibleFrame,
            selectionFrame: globalSelection
        )

        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        applyControlState(.preparing)

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.target = self
        saveButton.action = #selector(save)
        pinButton.target = self
        pinButton.action = #selector(pin)
        copyButton.target = self
        copyButton.action = #selector(copyImage)

        let effectView = NSVisualEffectView(frame: NSRect(
            origin: .zero,
            size: ScrollingCapturePanelLayout.contentSize
        ))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = ScrollingCapturePanelLayout.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        let statusImage = NSImageView(image: NSImage(
            systemSymbolName: "rectangle.stack.fill",
            accessibilityDescription: "滚动截屏"
        )!)
        statusImage.contentTintColor = .systemCyan
        statusImage.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        statusImage.setContentHuggingPriority(.required, for: .horizontal)

        let statusStack = NSStackView(views: [statusImage, statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 7
        statusStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator
        separator.setContentHuggingPriority(.required, for: .horizontal)
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let actionsStack = NSStackView(
            views: [cancelButton, saveButton, pinButton, copyButton]
        )
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = 6
        actionsStack.setContentHuggingPriority(.required, for: .horizontal)

        let rootStack = NSStackView(views: [statusStack, separator, actionsStack])
        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 13),
            rootStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            rootStack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 28),
        ])
        panel.contentView = effectView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        borderController.present()
        window?.orderFrontRegardless()
    }

    func update(frameCount: Int, pixelHeight: Int) {
        applyControlState(.capturing)
        statusLabel.stringValue = ScrollingCapturePanelLayout.progressText(
            isAutomatic: mode == .automatic,
            frameCount: frameCount,
            pixelHeight: pixelHeight
        )
    }

    func showExporting() {
        borderController.dismiss()
        statusLabel.stringValue = "正在生成分享长图…"
        applyControlState(.exporting)
    }

    func finish() {
        borderController.dismiss()
        close()
    }

    @objc private func cancel() {
        guard !stopRequested, controlState.allowsCancellation else { return }
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
        guard !stopRequested, controlState.allowsOutput else { return }
        stopRequested = true
        showExporting()
        onStop?(action)
    }

    private func applyControlState(_ state: ScrollingCaptureControlState) {
        controlState = state
        cancelButton.isEnabled = state.allowsCancellation
        saveButton.isEnabled = state.allowsOutput
        pinButton.isEnabled = state.allowsOutput
        copyButton.isEnabled = state.allowsOutput
    }

    private static func iconButton(symbol: String, help: String) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: help
        )
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }

    private static func actionButton(
        title: String,
        symbol: String,
        help: String
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: help
        )
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = help
        button.setAccessibilityLabel(help)
        return button
    }
}
