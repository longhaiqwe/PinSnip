import Carbon
import Foundation
import PinSnipCore

@MainActor
final class GlobalHotKeyCenter {
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

    init(handler: @escaping (Identifier) -> Void) {
        self.handler = handler
        installEventHandler()
    }

    @discardableResult
    func register(_ settings: HotKeySettings) -> Bool {
        guard settings.isValid else { return false }
        let previousSettings = activeSettings

        unregisterHotKeys()
        if registerAll(settings) {
            activeSettings = settings
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
        setCaptureCancellationEnabled(false)
        unregisterHotKeys()
        activeSettings = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
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
