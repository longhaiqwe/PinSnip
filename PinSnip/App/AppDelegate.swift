import AppKit
import PinSnipCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pinManager = PinWindowManager()
    private lazy var captureCoordinator = CaptureCoordinator(pinManager: pinManager)
    private lazy var router = AppCommandRouter { [weak self] command in
        self?.perform(command)
    }
    private let hotKeySettingsStore = HotKeySettingsStore()
    private var hotKeySettings = HotKeySettings.standard
    private var hotKeyCenter: GlobalHotKeyCenter?
    private var hotKeySettingsWindowController: HotKeySettingsWindowController?
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var pasteMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotKeySettings = hotKeySettingsStore.load()
        configureStatusItem()
        let hotKeys = GlobalHotKeyCenter { [weak self] identifier in
            switch identifier {
            case .capture: self?.router.perform(.capture)
            case .paste: self?.router.perform(.paste)
            }
        }
        hotKeyCenter = hotKeys
        if !hotKeys.register(hotKeySettings) {
            showHotKeyWarning(for: hotKeySettings)
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
    @objc private func showHotKeySettings() {
        if let hotKeySettingsWindowController, hotKeySettingsWindowController.window?.isVisible == true {
            hotKeySettingsWindowController.showWindow(nil)
            return
        }
        let controller = HotKeySettingsWindowController(
            settings: hotKeySettings,
            applyHandler: { [weak self] settings in
                self?.applyHotKeySettings(settings) ?? false
            }
        )
        hotKeySettingsWindowController = controller
        controller.showWindow(nil)
    }
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
        let captureItem = menuItem("截图", action: #selector(capture))
        let pasteItem = menuItem("剪贴板贴图", action: #selector(paste))
        captureMenuItem = captureItem
        pasteMenuItem = pasteItem
        menu.addItem(captureItem)
        menu.addItem(pasteItem)
        menu.addItem(menuItem("快捷键设置…", action: #selector(showHotKeySettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("显示全部贴图", action: #selector(showPins)))
        menu.addItem(menuItem("隐藏全部贴图", action: #selector(hidePins)))
        menu.addItem(menuItem("恢复鼠标操作", action: #selector(restoreInteraction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 PinSnip", action: #selector(quit), shortcut: "q", modifiers: [.command]))
        item.menu = menu
        statusItem = item
        updateHotKeyMenuTitles()
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

    private func applyHotKeySettings(_ settings: HotKeySettings) -> Bool {
        guard settings.isValid else { return false }
        guard settings != hotKeySettings else { return true }
        guard hotKeyCenter?.register(settings) == true else { return false }

        hotKeySettingsStore.save(settings)
        hotKeySettings = settings
        updateHotKeyMenuTitles()
        return true
    }

    private func updateHotKeyMenuTitles() {
        captureMenuItem?.title = "截图（\(hotKeySettings.capture.displayName)）"
        pasteMenuItem?.title = "剪贴板贴图（\(hotKeySettings.paste.displayName)）"
    }

    private func showHotKeyWarning(for settings: HotKeySettings) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "PinSnip 快捷键注册失败"
        alert.informativeText = "\(settings.capture.displayName) 或 \(settings.paste.displayName) 已被 macOS 或其他应用占用，仍可从菜单栏使用全部功能。"
        alert.addButton(withTitle: "打开快捷键设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            showHotKeySettings()
        }
    }
}
