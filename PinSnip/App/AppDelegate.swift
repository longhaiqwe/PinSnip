import AppKit
import PinSnipCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let pinManager = PinWindowManager()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private lazy var captureCoordinator = CaptureCoordinator(
        pinManager: pinManager,
        shareStyle: shareStyle,
        borderSize: borderSize
    )
    private lazy var router = AppCommandRouter { [weak self] command in
        self?.perform(command)
    }
    private lazy var launchAtLoginManager = LaunchAtLoginManager(
        service: SMAppServiceLaunchAtLoginService()
    )
    private let hotKeySettingsStore = HotKeySettingsStore()
    private var hotKeySettings = HotKeySettings.standard
    private let shareStyleStore = ShareStyleStore()
    private var shareStyle = ShareStyle.dusk
    private var shelfEdgeMenuItems: [NSMenuItem] = []
    private var shareStyleMenuItems: [NSMenuItem] = []
    private let borderSizeStore = ShareBorderSizeStore()
    private var borderSize = ShareBorderSize.automatic
    private var borderSizeMenuItems: [NSMenuItem] = []
    private var customBorderSizeMenuItem: NSMenuItem?
    private var hotKeyCenter: GlobalHotKeyCenter?
    private var hotKeySettingsWindowController: HotKeySettingsWindowController?
    private var gifShareSettingsWindowController: GIFShareSettingsWindowController?
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var recordingMenuItem: NSMenuItem?
    private var pasteMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var updatesMenuItem: NSMenuItem?
    private var checkForUpdatesMenuItem: NSMenuItem?
    private var automaticUpdateChecksMenuItem: NSMenuItem?
    private var automaticUpdateDownloadsMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotKeySettings = hotKeySettingsStore.load()
        shareStyle = shareStyleStore.load()
        borderSize = borderSizeStore.load()
        captureCoordinator.prewarmCaptureAnalysis()
        configureStatusItem()
        updaterController.startUpdater()
        let hotKeys = GlobalHotKeyCenter { [weak self] identifier in
            switch identifier {
            case .capture: self?.router.perform(.capture)
            case .recording: self?.router.perform(.recordAnimatedGIF)
            case .paste: self?.router.perform(.paste)
            case .cancelActiveCapture: self?.captureCoordinator.cancelActiveCapture()
            }
        }
        hotKeyCenter = hotKeys
        captureCoordinator.onCaptureCancellationAvailabilityChanged = {
            [weak self] isAvailable in
            self?.hotKeyCenter?.setCaptureCancellationEnabled(isAvailable)
        }
        captureCoordinator.onShelfCaptureActivityChanged = { active in
            ShelfCoordinator.shared.setCaptureActive(active)
        }
        if !hotKeys.register(hotKeySettings) {
            showHotKeyWarning(for: hotKeySettings)
        }
        ShelfCoordinator.shared.onCaptureRequested = { [weak self] in self?.router.perform(.capture) }
        ShelfCoordinator.shared.start(pinManager: pinManager)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShelfCoordinator.shared.shutdown()
        hotKeyCenter?.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard captureCoordinator.isExportingCapture || captureCoordinator.hasUnexportedGIFs else { return .terminateNow }
        let alert = NSAlert()
        if captureCoordinator.isExportingCapture {
            alert.messageText = "正在处理截图或动图"
            alert.informativeText = "请完成当前输出后再退出 PinSnip。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return .terminateCancel
        }
        alert.alertStyle = .warning
        alert.messageText = "还有动图未导出"
        alert.informativeText = "返回后可在动图窗口重试复制或另存为。退出会丢弃尚未存入晾衣架的动图。"
        alert.addButton(withTitle: "返回继续处理")
        let discard = alert.addButton(withTitle: "丢弃并退出")
        discard.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    @objc private func capture() { router.perform(.capture) }
    @objc private func captureScrolling() { router.perform(.captureScrolling) }
    @objc private func recordAnimatedGIF() { router.perform(.recordAnimatedGIF) }
    @objc private func captureLastRegion() { router.perform(.captureLastRegion) }
    @objc private func paste() { router.perform(.paste) }
    @objc private func showPins() { router.perform(.showAllPins) }
    @objc private func hidePins() { router.perform(.hideAllPins) }
    @objc private func checkForUpdates() { router.perform(.checkForUpdates) }
    @objc private func toggleAutomaticUpdateChecks() {
        router.perform(.toggleAutomaticUpdateChecks)
    }
    @objc private func toggleAutomaticUpdateDownloads() {
        router.perform(.toggleAutomaticUpdateDownloads)
    }
    @objc private func toggleLaunchAtLogin() {
        router.perform(.toggleLaunchAtLogin)
    }
    @objc private func toggleShelf() {
        ShelfCoordinator.shared.toggleForKeyboardInteraction()
    }
    @objc private func openShelfStorage() {
        ShelfCoordinator.shared.openStorageFolder()
    }
    @objc private func restoreArchivedShelfItems() {
        ShelfCoordinator.shared.restoreArchivedItems()
    }
    @objc private func selectShelfEdge(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let edge = ShelfEdge(rawValue: rawValue) else { return }
        ShelfCoordinator.shared.setEdge(edge)
        updateShelfEdgeMenuState()
    }

    private func updateShelfEdgeMenuState() {
        for item in shelfEdgeMenuItems {
            item.state = (item.representedObject as? String) == ShelfCoordinator.shared.edge.rawValue ? .on : .off
        }
    }

    @objc private func restoreInteraction() { pinManager.makeAllInteractive() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticUpdateDownloads) {
            return updateMenuState.canToggleAutomaticDownloads
        }
        guard menuItem.action == #selector(restoreInteraction) else { return true }
        return pinManager.hasClickThroughPins
    }

    @objc private func selectShareStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = ShareStyle(rawValue: rawValue)
        else { return }
        shareStyle = style
        shareStyleStore.save(style)
        captureCoordinator.updateShareStyle(style)
        updateShareStyleMenuState()
    }
    @objc private func selectBorderSize(_ sender: NSMenuItem) {
        applyBorderSize(ShareBorderSize(pixels: sender.tag == 0 ? nil : sender.tag))
    }

    @objc private func customizeBorderSize() {
        let alert = NSAlert()
        alert.messageText = "设置边框大小"
        alert.informativeText = "输入每侧边框的宽度（8–300 像素）。适用于自动配色和所有固定渐变背景，按导出图片像素计算。"
        let input = NSTextField(string: String(borderSize.pixels ?? 48))
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        input.setAccessibilityLabel("每侧边框宽度（像素）")
        alert.accessoryView = input
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let pixels = Int(input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ShareBorderSize.pixelRange.contains(pixels) else {
                alert.informativeText = "请输入 8–300 之间的整数，单位为导出图片的像素。"
                continue
            }
            applyBorderSize(ShareBorderSize(pixels: pixels))
            break
        }
    }

    private func applyBorderSize(_ size: ShareBorderSize) {
        borderSize = size
        borderSizeStore.save(size)
        captureCoordinator.updateBorderSize(size)
        updateShareStyleMenuState()
    }

    @objc private func showGIFShareSettings() {
        if let controller = gifShareSettingsWindowController, controller.window?.isVisible == true {
            controller.showWindow(nil)
            return
        }
        let controller = GIFShareSettingsWindowController()
        gifShareSettingsWindowController = controller
        controller.showWindow(nil)
    }

    @objc private func showHotKeySettings() {
        if let hotKeySettingsWindowController, hotKeySettingsWindowController.window?.isVisible == true {
            hotKeySettingsWindowController.showWindow(nil)
            return
        }
        let controller = HotKeySettingsWindowController(
            settings: hotKeySettings,
            recordingStateChanged: { [weak self] isRecording in
                guard let self else { return }
                if self.hotKeyCenter?.setShortcutRecordingEnabled(isRecording) == false {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.showHotKeyWarning(for: self.hotKeySettings)
                    }
                }
            },
            registrationFailures: { [weak self] in self?.hotKeyCenter?.lastRegistrationFailures ?? [] },
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
        case .capture: captureCoordinator.startCapture(trackingMenus: hotKeyCenter?.trackingMenus ?? [])
        case .captureScrolling: captureCoordinator.startScrollingCaptureSelection()
        case .recordAnimatedGIF: captureCoordinator.startGIFRecordingSelection(trackingMenus: hotKeyCenter?.trackingMenus ?? [])
        case .captureLastRegion: captureCoordinator.startLastRegionCapture()
        case .paste:
            var result = captureCoordinator.pinNextCapturedScreenshot()
            if case .useClipboard = result {
                guard !pinManager.pinClipboard() else { return }
                // An unreadable image file must not block the next screenshot in history.
                result = captureCoordinator.pinNextCapturedScreenshot()
            }
            switch result {
            case .useClipboard: TransientFeedback.show(message: "剪贴板中没有可贴出的图片。")
            case .historyExhausted:
                TransientFeedback.show(message: "最近的截图已全部贴出。")
            case .pinned: break
            }
        case .showAllPins: pinManager.showAll()
        case .hideAllPins: pinManager.hideAll()
        case .checkForUpdates:
            updaterController.checkForUpdates(nil)
        case .toggleAutomaticUpdateChecks:
            let updater = updaterController.updater
            updater.automaticallyChecksForUpdates.toggle()
            updateUpdateMenuState()
        case .toggleAutomaticUpdateDownloads:
            let updater = updaterController.updater
            guard updateMenuState.canToggleAutomaticDownloads else { return }
            updater.automaticallyDownloadsUpdates.toggle()
            updateUpdateMenuState()
        case .toggleLaunchAtLogin:
            do {
                let newStatus = try launchAtLoginManager.toggle()
                if newStatus == .requiresApproval {
                    showLaunchAtLoginApprovalAlert()
                }
            } catch {
                showLaunchAtLoginErrorAlert(error)
            }
            updateLaunchAtLoginMenuState()
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
            button.toolTip = "PinSnip — 截图、滚动截屏、动图录制与贴图"
        }

        let menu = NSMenu()
        let captureItem = menuItem("截图", action: #selector(capture))
        let scrollingItem = menuItem("滚动截屏…", action: #selector(captureScrolling))
        let recordingItem = menuItem("录制动图…", action: #selector(recordAnimatedGIF))
        let pasteItem = menuItem("贴图", action: #selector(paste))
        pasteItem.toolTip = "优先贴出新复制的图片，否则按顺序贴出最近的截图"
        captureMenuItem = captureItem
        recordingMenuItem = recordingItem
        pasteMenuItem = pasteItem
        menu.addItem(captureItem)
        menu.addItem(scrollingItem)
        menu.addItem(recordingItem)
        menu.addItem(menuItem("重复上次区域", action: #selector(captureLastRegion)))
        menu.addItem(pasteItem)
        menu.addItem(menuItem("暂存晾衣架", action: #selector(toggleShelf)))
        menu.addItem(.separator())
        menu.addItem(submenuItem("截图与贴图管理", menu: makeImageManagementMenu()))
        menu.addItem(submenuItem("图片样式", menu: makeImageStyleMenu()))
        menu.addItem(submenuItem("设置", menu: makeSettingsMenu()))
        let updatesItem = submenuItem("更新", menu: makeUpdatesMenu())
        updatesMenuItem = updatesItem
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            menu.addItem(.sectionHeader(title: "当前版本 \(version)"))
        }
        menu.addItem(menuItem("退出 PinSnip", action: #selector(quit), shortcut: "q", modifiers: [.command]))
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateHotKeyMenuTitles()
        updateShelfEdgeMenuState()
        updateShareStyleMenuState()
        updateUpdateMenuState()
        updateLaunchAtLoginMenuState()
    }

    private func makeImageManagementMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "晾衣架"))
        menu.addItem(menuItem("打开本地截图文件夹", action: #selector(openShelfStorage)))
        menu.addItem(menuItem("恢复已取下的截图", action: #selector(restoreArchivedShelfItems)))
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "贴图"))
        menu.addItem(menuItem("显示全部贴图", action: #selector(showPins)))
        menu.addItem(menuItem("隐藏全部贴图", action: #selector(hidePins)))
        menu.addItem(menuItem("关闭贴图鼠标穿透", action: #selector(restoreInteraction)))
        return menu
    }

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("快捷键设置…", action: #selector(showHotKeySettings)))
        menu.addItem(menuItem("GIF 分享大小…", action: #selector(showGIFShareSettings)))
        let launchAtLoginItem = menuItem("开机启动", action: #selector(toggleLaunchAtLogin))
        launchAtLoginMenuItem = launchAtLoginItem
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "晾衣架位置"))
        shelfEdgeMenuItems = ShelfEdge.allCases.map { edge in
            let item = menuItem(edge.title, action: #selector(selectShelfEdge(_:)))
            item.representedObject = edge.rawValue
            menu.addItem(item)
            return item
        }
        return menu
    }

    private func makeImageStyleMenu() -> NSMenu {
        let menu = NSMenu()
        shareStyleMenuItems = ShareStyle.allCases.map { style in
            let item = menuItem(style.title, action: #selector(selectShareStyle(_:)))
            item.representedObject = style.rawValue
            menu.addItem(item)
            return item
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "边框大小"))
        borderSizeMenuItems = [0, 24, 48, 80, 120].map { pixels in
            let item = menuItem(
                pixels == 0 ? "自动" : "\(pixels) 像素",
                action: #selector(selectBorderSize(_:))
            )
            item.tag = pixels
            menu.addItem(item)
            return item
        }
        let customSizeItem = menuItem("自定义…", action: #selector(customizeBorderSize))
        customBorderSizeMenuItem = customSizeItem
        menu.addItem(customSizeItem)
        return menu
    }

    private func makeUpdatesMenu() -> NSMenu {
        let menu = NSMenu()
        let checkForUpdatesItem = menuItem("检查更新…", action: #selector(checkForUpdates))
        checkForUpdatesMenuItem = checkForUpdatesItem
        menu.addItem(checkForUpdatesItem)
        let automaticChecksItem = menuItem(
            "自动检查更新",
            action: #selector(toggleAutomaticUpdateChecks)
        )
        let automaticDownloadsItem = menuItem(
            "自动下载并安装更新",
            action: #selector(toggleAutomaticUpdateDownloads)
        )
        automaticUpdateChecksMenuItem = automaticChecksItem
        automaticUpdateDownloadsMenuItem = automaticDownloadsItem
        menu.addItem(automaticChecksItem)
        menu.addItem(automaticDownloadsItem)
        return menu
    }

    private func submenuItem(_ title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
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
        guard hotKeyCenter?.register(settings) == true else { return false }

        hotKeySettingsStore.save(settings)
        hotKeySettings = settings
        updateHotKeyMenuTitles()
        return true
    }

    private func updateHotKeyMenuTitles() {
        captureMenuItem?.title = "截图（\(hotKeySettings.capture.displayName)）"
        recordingMenuItem?.title = "录制动图…（\(hotKeySettings.recording.displayName)）"
        pasteMenuItem?.title = "贴图（\(hotKeySettings.paste.displayName)）"
    }

    private func updateShareStyleMenuState() {
        for item in shareStyleMenuItems {
            item.state = item.representedObject as? String == shareStyle.rawValue ? .on : .off
        }
        for item in borderSizeMenuItems {
            item.state = item.tag == (borderSize.pixels ?? 0) ? .on : .off
        }
        let isCustom = borderSize.pixels.map { pixels in
            !borderSizeMenuItems.contains { $0.tag == pixels }
        } ?? false
        customBorderSizeMenuItem?.state = isCustom ? .on : .off
        customBorderSizeMenuItem?.title = isCustom
            ? "自定义（\(borderSize.pixels ?? 48) 像素）…" : "自定义…"
    }

    private var updateMenuState: UpdateMenuState {
        let updater = updaterController.updater
        return UpdateMenuState(
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates,
            allowsAutomaticUpdates: updater.allowsAutomaticUpdates
        )
    }

    private func updateUpdateMenuState() {
        let state = updateMenuState
        automaticUpdateChecksMenuItem?.state = state.automaticallyChecksForUpdates ? .on : .off
        automaticUpdateDownloadsMenuItem?.state = state.automaticallyDownloadsUpdates ? .on : .off
        automaticUpdateDownloadsMenuItem?.isEnabled = state.canToggleAutomaticDownloads
    }

    private func applyUpdateReminderState(_ state: UpdateReminderState) {
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: state.statusSymbolName,
                accessibilityDescription: state.availableVersion == nil
                    ? "PinSnip"
                    : "PinSnip 有新版本"
            )
            button.image?.isTemplate = true
        }
        checkForUpdatesMenuItem?.title = state.updateActionTitle
        updatesMenuItem?.title = state.availableVersion.map { "更新到 \($0)" } ?? "更新"
    }

    private func showHotKeyWarning(for settings: HotKeySettings) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "PinSnip 快捷键注册失败"
        let failures = hotKeyCenter?.lastRegistrationFailures ?? []
        let actions: [(GlobalHotKeyCenter.Identifier, String, HotKeyShortcut)] = [
            (.capture, "截图", settings.capture),
            (.recording, "录制动图", settings.recording),
            (.paste, "贴图", settings.paste),
        ]
        let failed = actions.filter { failures.contains($0.0) }
            .map { "\($0.1)（\($0.2.displayName)）" }.joined(separator: "、")
        alert.informativeText = failed.isEmpty
            ? "仍可从菜单栏使用功能。可打开快捷键设置重新保存。"
            : "\(failed)可能已被 macOS 或其他应用占用。仍可从菜单栏使用功能。"
        alert.addButton(withTitle: "打开快捷键设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            showHotKeySettings()
        }
    }

    private func updateLaunchAtLoginMenuState() {
        launchAtLoginMenuItem?.state = launchAtLoginManager.isEnabled ? .on : .off
    }

    private func showLaunchAtLoginApprovalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要允许 PinSnip 在后台运行"
        alert.informativeText = "PinSnip 的开机启动权限尚未获批或已被禁用。请在系统设置的「登录项与扩展」中允许 PinSnip，即可实现开机自启。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            launchAtLoginManager.openSystemSettings()
        }
    }

    private func showLaunchAtLoginErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "开机启动设置失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuState()
        updateUpdateMenuState()
    }
}

extension AppDelegate: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        applyUpdateReminderState(
            UpdateReminderState(availableVersion: update.displayVersionString)
        )
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        applyUpdateReminderState(UpdateReminderState(availableVersion: nil))
    }

    func standardUserDriverWillFinishUpdateSession() {
        applyUpdateReminderState(UpdateReminderState(availableVersion: nil))
    }
}
