import Foundation

/// Zero disables an individual limit. Limits apply to shared copies, never shelf originals.
public struct GIFShareSettings: Equatable, Sendable {
    public static let standard = GIFShareSettings(maximumWidth: 1280, maximumHeight: 1080, maximumBytes: 15_000_000)
    public static let compact = GIFShareSettings(maximumWidth: 640, maximumHeight: 640, maximumBytes: 1_000_000)
    public static let original = GIFShareSettings(maximumWidth: 0, maximumHeight: 0, maximumBytes: 0)
    public let maximumWidth: Int
    public let maximumHeight: Int
    public let maximumBytes: Int

    public init(maximumWidth: Int, maximumHeight: Int, maximumBytes: Int) {
        self.maximumWidth = maximumWidth == 0 ? 0 : min(4096, max(128, maximumWidth))
        self.maximumHeight = maximumHeight == 0 ? 0 : min(4096, max(128, maximumHeight))
        self.maximumBytes = maximumBytes == 0 ? 0 : min(50_000_000, max(100_000, maximumBytes))
    }
}

public final class GIFShareSettingsStore {
    private let defaults: UserDefaults
    private let key = "PinSnip.GIFShareSettings.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> GIFShareSettings {
        guard let values = defaults.dictionary(forKey: key),
              let width = values["maximumWidth"] as? Int,
              let height = values["maximumHeight"] as? Int,
              let bytes = values["maximumBytes"] as? Int else { return .standard }
        return GIFShareSettings(maximumWidth: width, maximumHeight: height, maximumBytes: bytes)
    }

    public func save(_ settings: GIFShareSettings) {
        defaults.set([
            "maximumWidth": settings.maximumWidth,
            "maximumHeight": settings.maximumHeight,
            "maximumBytes": settings.maximumBytes
        ], forKey: key)
    }
}
