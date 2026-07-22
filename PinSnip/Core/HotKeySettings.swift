import Foundation

public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let control = HotKeyModifiers(rawValue: 1 << 2)
    public static let shift = HotKeyModifiers(rawValue: 1 << 3)
}

public struct HotKeyShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: HotKeyModifiers

    public init(keyCode: UInt16, modifiers: HotKeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isValid: Bool {
        Self.functionKeyCodes.contains(keyCode)
            || !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
}

public struct HotKeySettings: Codable, Equatable, Sendable {
    public let capture: HotKeyShortcut
    public let recording: HotKeyShortcut
    public let paste: HotKeyShortcut

    public init(
        capture: HotKeyShortcut,
        recording: HotKeyShortcut,
        paste: HotKeyShortcut
    ) {
        self.capture = capture
        self.recording = recording
        self.paste = paste
    }

    public static let standard = HotKeySettings(
        capture: HotKeyShortcut(keyCode: 122),
        recording: HotKeyShortcut(keyCode: 99),
        paste: HotKeyShortcut(keyCode: 118)
    )

    public var isValid: Bool {
        capture.isValid
            && recording.isValid
            && paste.isValid
            && capture != recording
            && capture != paste
            && recording != paste
    }
}

public final class HotKeySettingsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "PinSnip.HotKeySettings.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> HotKeySettings {
        guard let data = defaults.data(forKey: key) else { return .standard }
        let decoder = JSONDecoder()
        if let settings = try? decoder.decode(HotKeySettings.self, from: data),
           settings.isValid {
            return settings
        }
        guard let legacy = try? decoder.decode(LegacyHotKeySettings.self, from: data),
              legacy.capture.isValid,
              legacy.paste.isValid,
              legacy.capture != legacy.paste
        else { return .standard }
        return Self.migrate(legacy)
    }

    public func save(_ settings: HotKeySettings) {
        guard settings.isValid, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    private static func migrate(_ legacy: LegacyHotKeySettings) -> HotKeySettings {
        let preferredRecording = HotKeyShortcut(keyCode: 99)
        let fallbackFunctionKeys = [118, 96, 97, 98, 100, 101, 109, 103, 111]
            .map { HotKeyShortcut(keyCode: UInt16($0)) }
        var recording = preferredRecording
        var paste = legacy.paste

        if paste == recording {
            paste = fallbackFunctionKeys.first {
                $0 != legacy.capture && $0 != recording
            } ?? HotKeySettings.standard.paste
        }
        if recording == legacy.capture {
            recording = fallbackFunctionKeys.first {
                $0 != legacy.capture && $0 != paste
            } ?? HotKeySettings.standard.recording
        }

        let migrated = HotKeySettings(
            capture: legacy.capture,
            recording: recording,
            paste: paste
        )
        return migrated.isValid ? migrated : .standard
    }
}

private struct LegacyHotKeySettings: Decodable {
    let capture: HotKeyShortcut
    let paste: HotKeyShortcut
}
