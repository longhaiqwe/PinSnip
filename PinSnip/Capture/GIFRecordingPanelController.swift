import AppKit
import PinSnipCore

@MainActor
final class GIFRecordingPanelController: NSWindowController {
    private let statusLabel: NSTextField
    private let cancelButton: NSButton
    private let saveButton: NSButton
    private let copyButton: NSButton
    private let borderController: GIFRecordingBorderController
    private let startedAt = Date()
    private var timer: Timer?
    private var stopRequested = false
    var onCancel: (() -> Void)?
    var onStop: ((GIFRecordingOutputAction) -> Void)?

    init(screen: NSScreen, selectionRect: CGRect) {
        let statusLabel = NSTextField(labelWithString:
            GIFRecordingPanelLayout.progressText(
                elapsedSeconds: 0,
                maximumSeconds: Int(ScreenGIFRecorder.maximumDuration)
            )
        )
        statusLabel.textColor = .labelColor
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cancelButton = Self.iconButton(symbol: "xmark", help: "取消动图录制")
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = Self.actionButton(
            title: "保存",
            symbol: "square.and.arrow.down",
            help: "停止并保存分享动图…"
        )
        let copyButton = Self.actionButton(
            title: "完成",
            symbol: "checkmark",
            help: "停止并复制分享动图"
        )
        copyButton.bezelColor = .controlAccentColor
        copyButton.contentTintColor = .white
        copyButton.keyEquivalent = "\r"
        self.statusLabel = statusLabel
        self.cancelButton = cancelButton
        self.saveButton = saveButton
        self.copyButton = copyButton
        borderController = GIFRecordingBorderController(
            screen: screen,
            selectionRect: selectionRect
        )

        let globalSelection = selectionRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let panelFrame = GIFRecordingPanelLayout.panelFrame(
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
        panel.hidesOnDeactivate = GIFRecordingPanelLayout.hidesOnDeactivate
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        super.init(window: panel)

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.target = self
        saveButton.action = #selector(requestSave)
        copyButton.target = self
        copyButton.action = #selector(requestCopy)

        let effectView = NSVisualEffectView(frame: NSRect(
            origin: .zero,
            size: GIFRecordingPanelLayout.contentSize
        ))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = GIFRecordingPanelLayout.cornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        let statusImage = NSImageView(image: NSImage(
            systemSymbolName: "record.circle.fill",
            accessibilityDescription: "正在录制动图"
        )!)
        statusImage.contentTintColor = .systemRed
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
            views: [cancelButton, saveButton, copyButton]
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
        statusLabel.stringValue = "正在生成分享动图…"
        statusLabel.textColor = .labelColor
        cancelButton.isEnabled = false
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

    @objc private func cancel() {
        guard !stopRequested else { return }
        stopRequested = true
        onCancel?()
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
        statusLabel.stringValue = GIFRecordingPanelLayout.progressText(
            elapsedSeconds: seconds,
            maximumSeconds: Int(ScreenGIFRecorder.maximumDuration)
        )
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
