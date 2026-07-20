import AppKit
import PinSnipCore

@MainActor
final class HotKeySettingsWindowController: NSWindowController {
    typealias ApplyHandler = (HotKeySettings) -> Bool

    private let captureRecorder: HotKeyRecorderControl
    private let pasteRecorder: HotKeyRecorderControl
    private let applyHandler: ApplyHandler
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(settings: HotKeySettings, applyHandler: @escaping ApplyHandler) {
        captureRecorder = HotKeyRecorderControl(shortcut: settings.capture)
        pasteRecorder = HotKeyRecorderControl(shortcut: settings.paste)
        self.applyHandler = applyHandler

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PinSnip 快捷键"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        super.init(window: window)
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "全局快捷键")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)

        let instructions = NSTextField(
            wrappingLabelWithString: "点击快捷键框后直接按下新组合。F1–F20 可单独使用；普通按键至少需要搭配 ⌘、⌥ 或 ⌃，也可再加 ⇧。"
        )
        instructions.textColor = .secondaryLabelColor

        captureRecorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        pasteRecorder.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let grid = NSGridView(views: [
            [label("截图"), captureRecorder],
            [label("剪贴板贴图"), pasteRecorder],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)

        let restoreButton = NSButton(title: "恢复 F1 / F3", target: self, action: #selector(restoreDefaults))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [restoreButton, spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [heading, instructions, grid, errorLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: instructions)
        stack.setCustomSpacing(18, after: errorLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }

    @objc private func restoreDefaults() {
        captureRecorder.shortcut = HotKeySettings.standard.capture
        pasteRecorder.shortcut = HotKeySettings.standard.paste
        errorLabel.stringValue = ""
    }

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        let settings = HotKeySettings(
            capture: captureRecorder.shortcut,
            paste: pasteRecorder.shortcut
        )
        guard settings.isValid else {
            errorLabel.stringValue = "截图与贴图需要使用两个不同且有效的快捷键。"
            NSSound.beep()
            return
        }
        guard applyHandler(settings) else {
            errorLabel.stringValue = "注册失败，快捷键可能已被 macOS 或其他应用占用。原设置仍然有效。"
            NSSound.beep()
            return
        }
        close()
    }
}
