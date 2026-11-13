import AppKit

/// Retains the only remaining GIF copy until output succeeds or the user discards it.
@MainActor
final class GIFOutputRecoveryController: NSWindowController {
    private(set) var pendingData: Data?
    private(set) var isWorking = false
    private let copyHandler: (Data, @escaping (CaptureOutputResult) -> Void) -> Void
    private let saveHandler: (Data) -> CaptureOutputResult
    private let isOnShelf: Bool
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "重试复制", target: nil, action: nil)
    private let saveButton = NSButton(title: "另存为…", target: nil, action: nil)
    private let discardButton = NSButton(title: "丢弃", target: nil, action: nil)
    var onFinish: (() -> Void)?

    var needsDiscardConfirmation: Bool { !isOnShelf && pendingData != nil }

    init(
        data: Data,
        result: CaptureOutputResult,
        isOnShelf: Bool = false,
        copyHandler: @escaping (Data, @escaping (CaptureOutputResult) -> Void) -> Void = {
            CaptureOutputService.copyGIFResult($0, completion: $1)
        },
        saveHandler: @escaping (Data) -> CaptureOutputResult = {
            CaptureOutputService.saveGIFResult($0)
        }
    ) {
        pendingData = data
        self.copyHandler = copyHandler
        self.saveHandler = saveHandler
        self.isOnShelf = isOnShelf
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "保留未导出的动图"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        super.init(window: panel)

        let heading = NSTextField(labelWithString: "动图尚未导出")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 166, width: 412, height: 25)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 69, width: 412, height: 85)
        statusLabel.maximumNumberOfLines = 5
        panel.contentView?.addSubview(heading)
        panel.contentView?.addSubview(statusLabel)

        for button in [copyButton, saveButton, discardButton] {
            button.target = self
            button.bezelStyle = .rounded
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .center
            panel.contentView?.addSubview(button)
        }
        discardButton.frame = NSRect(x: 20, y: 20, width: 70, height: 32)
        discardButton.action = #selector(discard)
        discardButton.title = isOnShelf ? "关闭" : "丢弃"
        discardButton.toolTip = isOnShelf ? "关闭窗口，动图仍在晾衣架中" : "放弃尚未导出的动图"
        saveButton.frame = NSRect(x: 216, y: 20, width: 106, height: 32)
        saveButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        saveButton.action = #selector(retrySave)
        copyButton.frame = NSRect(x: 326, y: 20, width: 114, height: 32)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.action = #selector(retryCopy)
        copyButton.keyEquivalent = "\r"
        copyButton.bezelColor = .controlAccentColor
        updateMessage(for: result)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func retryCopy() {
        guard !isWorking, let data = pendingData else { return }
        setWorking(true)
        statusLabel.stringValue = "正在复制，原动图仍保留在此窗口。"
        copyHandler(data) { [weak self] result in
            self?.completeAttempt(result)
        }
    }

    @objc func retrySave() {
        guard !isWorking, let data = pendingData else { return }
        setWorking(true)
        completeAttempt(saveHandler(data))
    }

    @objc func discard() {
        guard !isWorking else { return }
        finish()
    }

    private func completeAttempt(_ result: CaptureOutputResult) {
        setWorking(false)
        if result.succeeded { finish() }
        else { updateMessage(for: result) }
    }

    private func setWorking(_ working: Bool) {
        isWorking = working
        for button in [copyButton, saveButton, discardButton] { button.isEnabled = !working }
    }

    private func updateMessage(for result: CaptureOutputResult) {
        let detail: String
        switch result {
        case .succeeded: detail = ""
        case .cancelled: detail = "已取消另存。"
        case let .failed(error): detail = error.localizedDescription
        }
        statusLabel.stringValue = (isOnShelf
            ? "动图已保留在晾衣架中，可重试复制或另存为。"
            : "动图未能存入晾衣架。原动图仍保留在此窗口，可重试复制或另存为；点击“丢弃”才会移除。") + "\n" + detail
    }

    private func finish() {
        guard pendingData != nil else { return }
        pendingData = nil
        close()
        onFinish?()
    }
}

enum CaptureSaveFeedback {
    static func message(for result: CaptureOutputResult, isOnShelf: Bool, isGIF: Bool = false) -> String? {
        guard isOnShelf, !result.succeeded else { return nil }
        let item = isGIF ? "动图" : "截图"
        switch result {
        case .succeeded: return nil
        case .cancelled: return "未另存；\(item)已保留在晾衣架，可拖到访达导出。"
        case .failed: return "导出失败；\(item)已保留在晾衣架，可拖到访达导出。"
        }
    }
}
