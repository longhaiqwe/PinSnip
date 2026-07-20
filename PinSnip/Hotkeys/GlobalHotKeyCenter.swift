import Carbon
import Foundation

@MainActor
final class GlobalHotKeyCenter {
    enum Identifier: UInt32 {
        case capture = 1
        case paste = 2
    }

    private let handler: (Identifier) -> Void
    private var hotKeys: [Identifier: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x504E5350

    init(handler: @escaping (Identifier) -> Void) {
        self.handler = handler
        installEventHandler()
    }

    @discardableResult
    func registerDefaults() -> Bool {
        let capture = register(.capture, keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(controlKey | shiftKey))
        let paste = register(.paste, keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(controlKey | shiftKey))
        return capture && paste
    }

    func shutdown() {
        for reference in hotKeys.values {
            UnregisterEventHotKey(reference)
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(_ identifier: Identifier, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
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

