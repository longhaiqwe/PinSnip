import AppKit
import PinSnipCore

@MainActor
final class HotKeySettingsWindowController: NSWindowController, NSWindowDelegate {
    typealias ApplyHandler = (HotKeySettings) -> Bool

    private let captureRecorder: HotKeyRecorderControl
    private let recordingRecorder: HotKeyRecorderControl
    private let pasteRecorder: HotKeyRecorderControl
    private let applyHandler: ApplyHandler
    private let recordingStateChanged: (Bool) -> Void
    private let registrationFailures: () -> [GlobalHotKeyCenter.Identifier]
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private static var lastWindowFrame: NSRect?

    init(settings: HotKeySettings, recordingStateChanged: @escaping (Bool) -> Void = { _ in },
         registrationFailures: @escaping () -> [GlobalHotKeyCenter.Identifier] = { [] },
         applyHandler: @escaping ApplyHandler) {
        captureRecorder = HotKeyRecorderControl(shortcut: settings.capture)
        recordingRecorder = HotKeyRecorderControl(shortcut: settings.recording)
        pasteRecorder = HotKeyRecorderControl(shortcut: settings.paste)
        self.applyHandler = applyHandler
        self.recordingStateChanged = recordingStateChanged
        self.registrationFailures = registrationFailures

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PinSnip 快捷键"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.delegate = self
        configureContent()
        if let frame = Self.lastWindowFrame { window.setFrame(frame, display: false) }
        else { window.center() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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
        recordingRecorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        pasteRecorder.widthAnchor.constraint(equalToConstant: 220).isActive = true
        for (recorder, name) in [(captureRecorder, "截图快捷键"),
                                 (recordingRecorder, "录制动图快捷键"),
                                 (pasteRecorder, "贴图快捷键")] {
            recorder.setAccessibilityLabel(name)
            recorder.onRecordingChanged = { [weak self] in
                guard let self else { return }
                self.recordingStateChanged(self.recorders.contains { $0.isRecording })
            }
            recorder.onShortcutChanged = { [weak self] in self?.errorLabel.stringValue = "" }
        }

        let grid = NSGridView(views: [
            [label("截图"), captureRecorder],
            [label("录制动图"), recordingRecorder],
            [label("贴图"), pasteRecorder],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        let pasteHint = NSTextField(wrappingLabelWithString: "贴图优先使用新复制的图片，否则从新到旧逐张贴出最近截图。")
        pasteHint.font = .systemFont(ofSize: 12)
        pasteHint.textColor = .secondaryLabelColor

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)

        let restoreButton = NSButton(title: "恢复 F1 / F3 / F4", target: self, action: #selector(restoreDefaults))
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

        let stack = NSStackView(views: [heading, instructions, grid, pasteHint, errorLabel, buttonRow])
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
            pasteHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
        stopRecording()
        captureRecorder.shortcut = HotKeySettings.standard.capture
        recordingRecorder.shortcut = HotKeySettings.standard.recording
        pasteRecorder.shortcut = HotKeySettings.standard.paste
        errorLabel.stringValue = ""
    }

    @objc private func cancel() {
        stopRecording()
        close()
    }

    @objc private func save() {
        stopRecording()
        let settings = HotKeySettings(
            capture: captureRecorder.shortcut,
            recording: recordingRecorder.shortcut,
            paste: pasteRecorder.shortcut
        )
        guard settings.isValid else {
            let entries = namedRecorders
            if let invalid = entries.first(where: { !$0.recorder.shortcut.isValid }) {
                showError("\(invalid.name)的快捷键无效。普通按键需搭配 ⌘、⌥ 或 ⌃。", focus: invalid.recorder)
            } else {
                for index in 1..<entries.count {
                    if let previous = entries[..<index].first(where: { $0.recorder.shortcut == entries[index].recorder.shortcut }) {
                        showError("\(previous.name)与\(entries[index].name)都使用 \(entries[index].recorder.shortcut.displayName)，请修改其中一个。", focus: entries[index].recorder)
                        break
                    }
                }
            }
            return
        }
        guard applyHandler(settings) else {
            let failed = namedRecorders.filter { registrationFailures().contains($0.identifier) }
            if let first = failed.first {
                let names = failed.map { "\($0.name)（\($0.recorder.shortcut.displayName)）" }.joined(separator: "、")
                showError("未保存：\(names)注册失败，可能已被系统或其他应用占用。请修改后重试。", focus: first.recorder)
            } else {
                showError("未保存，快捷键注册失败。请换一组快捷键，仍可从菜单栏使用功能。", focus: captureRecorder)
            }
            return
        }
        close()
    }

    private var recorders: [HotKeyRecorderControl] {
        [captureRecorder, recordingRecorder, pasteRecorder]
    }

    private var namedRecorders: [(identifier: GlobalHotKeyCenter.Identifier, name: String, recorder: HotKeyRecorderControl)] {
        [(.capture, "截图", captureRecorder), (.recording, "录制动图", recordingRecorder), (.paste, "贴图", pasteRecorder)]
    }

    private func showError(_ message: String, focus recorder: HotKeyRecorderControl) {
        errorLabel.stringValue = message
        window?.makeFirstResponder(recorder)
        NSSound.beep()
    }

    private func stopRecording() {
        for recorder in recorders { recorder.cancelRecording() }
    }

    func windowDidResignKey(_ notification: Notification) { stopRecording() }
    func windowWillClose(_ notification: Notification) {
        Self.lastWindowFrame = window?.frame
        stopRecording()
    }
}
