import AppKit
import Carbon
import PinSnipCore

@MainActor
final class HotKeyRecorderControl: NSButton {
    var shortcut: HotKeyShortcut {
        didSet { updateTitle() }
    }
    var onRecordingChanged: (() -> Void)?
    var onShortcutChanged: (() -> Void)?

    private(set) var isRecording = false {
        didSet {
            updateTitle()
            if isRecording != oldValue { onRecordingChanged?() }
        }
    }

    init(shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        toolTip = "点击后按下新的快捷键；Esc 取消本次录入"
        setAccessibilityLabel("快捷键")
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        // Capture Return, Escape and Command combinations before window buttons
        // or menus interpret them as save, cancel or another action.
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        guard !event.isARepeat else { return }
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }

        let candidate = HotKeyShortcut(event: event)
        guard candidate.isValid else {
            NSSound.beep()
            title = "普通按键需加修饰键"
            return
        }

        shortcut = candidate
        isRecording = false
        onShortcutChanged?()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    @objc private func beginRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
    }

    func cancelRecording() {
        isRecording = false
    }

    private func updateTitle() {
        title = isRecording ? "请按快捷键…" : shortcut.displayName
    }
}
