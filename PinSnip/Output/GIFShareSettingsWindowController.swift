import AppKit
import PinSnipCore

@MainActor
final class GIFShareSettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let store: GIFShareSettingsStore
    private let presets = NSPopUpButton(frame: .zero, pullsDown: false)
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let bytesField = NSTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(store: GIFShareSettingsStore = GIFShareSettingsStore()) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 390),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "GIF 分享大小"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
        display(store.load())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        let heading = NSTextField(labelWithString: "控制复制出去的动图大小")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        let note = NSTextField(wrappingLabelWithString: "按比例缩小；体积过大时自动降低尺寸和帧率，保留完整播放时长。填写 0 表示该项不限制。")
        note.textColor = .secondaryLabelColor
        presets.addItems(withTitles: ["标准（15 MB）", "小体积（1 MB）", "原始大小 · 不压缩", "自定义"])
        presets.target = self
        presets.action = #selector(selectPreset)
        for (field, label) in [(widthField, "最大宽度（像素）"), (heightField, "最大高度（像素）"), (bytesField, "体积上限（MB）")] {
            field.delegate = self
            field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }
        presets.setAccessibilityLabel("GIF 分享预设")
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "预设"), presets],
            [NSTextField(labelWithString: "最大宽度（像素）"), widthField],
            [NSTextField(labelWithString: "最大高度（像素）"), heightField],
            [NSTextField(labelWithString: "体积上限（MB）"), bytesField]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        let scope = NSTextField(wrappingLabelWithString: "用于录制完成后的复制和晾衣架复制。保存、直接拖出仍使用原文件；目标应用是否显示为动图取决于其自身规则。")
        scope.font = .systemFont(ofSize: 12)
        scope.textColor = .secondaryLabelColor
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        for button in [cancel, save] {
            button.bezelStyle = .rounded
            button.alignment = .center
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, note, grid, scope, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scope.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func display(_ settings: GIFShareSettings) {
        widthField.stringValue = String(settings.maximumWidth)
        heightField.stringValue = String(settings.maximumHeight)
        bytesField.stringValue = String(format: "%g", Double(settings.maximumBytes) / 1_000_000)
        presets.selectItem(at: [GIFShareSettings.standard, .compact, .original].firstIndex(of: settings) ?? 3)
        errorLabel.stringValue = ""
    }

    @objc private func selectPreset() {
        let values: [GIFShareSettings] = [.standard, .compact, .original]
        if presets.indexOfSelectedItem < values.count { display(values[presets.indexOfSelectedItem]) }
    }

    func controlTextDidChange(_ obj: Notification) {
        presets.selectItem(at: 3)
        errorLabel.stringValue = ""
    }

    @objc private func save() {
        func trimmed(_ field: NSTextField) -> String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let width = Int(trimmed(widthField)), let height = Int(trimmed(heightField)),
              width == 0 || (128...4096).contains(width), height == 0 || (128...4096).contains(height),
              let megabytes = Double(trimmed(bytesField)), megabytes.isFinite,
              megabytes == 0 || (0.1...50).contains(megabytes) else {
            errorLabel.stringValue = "宽高请输入 128–4096 的整数，体积为 0.1–50 MB；0 表示不限制。"
            return
        }
        store.save(GIFShareSettings(maximumWidth: width, maximumHeight: height,
                                    maximumBytes: Int((megabytes * 1_000_000).rounded())))
        close()
    }

    @objc private func cancel() { close() }
}
