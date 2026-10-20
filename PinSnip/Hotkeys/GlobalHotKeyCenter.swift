import AppKit
import Carbon
import Foundation
import PinSnipCore

@MainActor
final class GlobalHotKeyCenter: NSObject {
    enum Identifier: UInt32 {
        case capture = 1
        case recording = 2
        case paste = 3
        case cancelActiveCapture = 4
    }

    private let handler: (Identifier) -> Void
    private var hotKeys: [Identifier: EventHotKeyRef] = [:]
    private var captureCancellationHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var activeSettings: HotKeySettings?
    private let signature: OSType = 0x504E5350
    private(set) var trackingMenus: [NSMenu] = []
    private var menuKeyMonitor: Any?
    private var menuKeyTimer: Timer?
    private var isReceivingMenuKey = false

    init(handler: @escaping (Identifier) -> Void) {
        self.handler = handler
        super.init()
        installEventHandler()
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil)
        installMenuKeyTimer()
    }

    @discardableResult
    func register(_ settings: HotKeySettings) -> Bool {
        guard settings.isValid else { return false }
        let previousSettings = activeSettings

        unregisterHotKeys()
        if registerAll(settings) {
            activeSettings = settings
            if !trackingMenus.isEmpty { unregisterHotKeys() }
            return true
        }

        unregisterHotKeys()
        if let previousSettings {
            if registerAll(previousSettings) {
                activeSettings = previousSettings
            } else {
                unregisterHotKeys()
                activeSettings = nil
            }
        }
        return false
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        stopMenuMonitoring()
        menuKeyTimer?.invalidate()
        menuKeyTimer = nil
        trackingMenus.removeAll()
        setCaptureCancellationEnabled(false)
        unregisterHotKeys()
        activeSettings = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    @objc private func menuBegan(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              !trackingMenus.contains(where: { $0 === menu }) else { return }
        trackingMenus.append(menu)
        guard trackingMenus.count == 1 else { return }
        // AppKit's menu loop consumes keyboard events before Carbon hotkeys.
        // Temporarily receive raw local keys instead; no accessibility permission is needed.
        unregisterHotKeys()
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleMenuKey(event) == true }
            return consumed ? nil : event
        }
    }

    private func installMenuKeyTimer() {
        // NSMenu can consume keys without NSApplication.sendEvent. Poll only in
        // its tracking mode, at a bounded rate so mouse movement stays responsive.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiveMenuKeyFromQueue() }
        }
        menuKeyTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    @objc private func menuEnded(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              trackingMenus.contains(where: { $0 === menu }) else { return }
        trackingMenus.removeAll { $0 === menu }
        guard trackingMenus.isEmpty else { return }
        stopMenuMonitoring()
        if let activeSettings, !registerAll(activeSettings) {
            NSLog("PinSnip: could not restore global shortcuts after menu tracking")
        }
    }

    private func stopMenuMonitoring() {
        if let menuKeyMonitor { NSEvent.removeMonitor(menuKeyMonitor) }
        menuKeyMonitor = nil
    }

    private func menuIdentifier(for event: NSEvent) -> Identifier? {
        guard !trackingMenus.isEmpty, event.type == .keyDown, let activeSettings else { return nil }
        // Only command/option/control/shift count; F-keys carry a synthesized Fn flag.
        let shortcut = HotKeyShortcut(event: event)
        if shortcut == activeSettings.capture { return .capture }
        if shortcut == activeSettings.recording { return .recording }
        if shortcut == activeSettings.paste { return .paste }
        return nil
    }

    private func handleMenuKey(_ event: NSEvent) -> Bool {
        guard let identifier = menuIdentifier(for: event) else { return false }
        if !event.isARepeat { handler(identifier) }
        return true
    }

    private func receiveMenuKeyFromQueue() {
        guard !trackingMenus.isEmpty, !isReceivingMenuKey else { return }
        isReceivingMenuKey = true
        defer { isReceivingMenuKey = false }
        // Look for a key without removing unrelated events. Context-menu loops
        // can leave app-defined/key-up events queued ahead of the shortcut.
        guard let key = NSApp.nextEvent(matching: .keyDown, until: .distantPast,
            inMode: .eventTracking, dequeue: false), menuIdentifier(for: key) != nil else { return }
        guard let event = NSApp.nextEvent(matching: .keyDown, until: .distantPast,
            inMode: .eventTracking, dequeue: true) else { return }
        _ = handleMenuKey(event)
    }

    @discardableResult
    func setCaptureCancellationEnabled(_ isEnabled: Bool) -> Bool {
        if !isEnabled {
            if let captureCancellationHotKey {
                UnregisterEventHotKey(captureCancellationHotKey)
                self.captureCancellationHotKey = nil
            }
            return true
        }
        guard captureCancellationHotKey == nil else { return true }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: signature,
            id: Identifier.cancelActiveCapture.rawValue
        )
        let status = RegisterEventHotKey(
            CapturePanelKeyboardShortcut.escapeKeyCode,
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        captureCancellationHotKey = reference
        return true
    }

    private func registerAll(_ settings: HotKeySettings) -> Bool {
        let capture = register(.capture, shortcut: settings.capture)
        let recording = register(.recording, shortcut: settings.recording)
        let paste = register(.paste, shortcut: settings.paste)
        return capture && recording && paste
    }

    private func unregisterHotKeys() {
        for reference in hotKeys.values {
            UnregisterEventHotKey(reference)
        }
        hotKeys.removeAll()
    }

    private func register(_ identifier: Identifier, shortcut: HotKeyShortcut) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier.rawValue)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        hotKeys[identifier] = reference
        return true
    }

    private func installEventHandler() {
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    if let identifier = Identifier(rawValue: hotKeyID.id) {
                        center.handler(identifier)
                    }
                }
                return noErr
            },
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

private extension HotKeyModifiers {
    var carbonValue: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}
