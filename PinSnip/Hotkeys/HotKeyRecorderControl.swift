import AppKit
import Carbon
import PinSnipCore

@MainActor
final class HotKeyRecorderControl: NSButton {
    var shortcut: HotKeyShortcut {
        didSet { updateTitle() }
    }

    private var isRecording = false {
        didSet { updateTitle() }
    }

    init(shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        toolTip = "点击后按下新的快捷键"
        setAccessibilityLabel("快捷键")
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
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
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    private func updateTitle() {
        title = isRecording ? "请按快捷键…" : shortcut.displayName
    }
}
