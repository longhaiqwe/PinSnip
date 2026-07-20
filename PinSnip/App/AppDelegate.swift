import AppKit
import PinSnipCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pinManager = PinWindowManager()
    private lazy var captureCoordinator = CaptureCoordinator(pinManager: pinManager)
    private lazy var router = AppCommandRouter { [weak self] command in
        self?.perform(command)
    }
    private var hotKeyCenter: GlobalHotKeyCenter?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        let hotKeys = GlobalHotKeyCenter { [weak self] identifier in
            switch identifier {
            case .capture: self?.router.perform(.capture)
            case .paste: self?.router.perform(.paste)
            }
        }
        hotKeyCenter = hotKeys
        if !hotKeys.registerDefaults() {
            showHotKeyWarning()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter?.shutdown()
    }

    @objc private func capture() { router.perform(.capture) }
    @objc private func paste() { router.perform(.paste) }
    @objc private func showPins() { router.perform(.showAllPins) }
    @objc private func hidePins() { router.perform(.hideAllPins) }
    @objc private func restoreInteraction() { pinManager.makeAllInteractive() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func perform(_ command: AppCommand) {
        switch command {
        case .capture: captureCoordinator.startCapture()
        case .paste: pinManager.pinClipboard()
        case .showAllPins: pinManager.showAll()
        case .hideAllPins: pinManager.hideAll()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.angled",
                accessibilityDescription: "PinSnip"
            )
            button.image?.isTemplate = true
            button.toolTip = "PinSnip — 截图与贴图"
        }

        let menu = NSMenu()
        menu.addItem(menuItem("截图", action: #selector(capture), shortcut: "1", modifiers: [.control, .shift]))
        menu.addItem(menuItem("剪贴板贴图", action: #selector(paste), shortcut: "2", modifiers: [.control, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem("显示全部贴图", action: #selector(showPins)))
        menu.addItem(menuItem("隐藏全部贴图", action: #selector(hidePins)))
        menu.addItem(menuItem("恢复鼠标操作", action: #selector(restoreInteraction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 PinSnip", action: #selector(quit), shortcut: "q", modifiers: [.command]))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        shortcut: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func showHotKeyWarning() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "PinSnip 快捷键注册失败"
        alert.informativeText = "⌃⇧1 或 ⌃⇧2 已被其他应用占用，仍可从菜单栏使用全部功能。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
