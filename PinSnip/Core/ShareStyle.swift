import Foundation

public enum ShareStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case paperCut
    case bordered
    case dusk
    case original

    public var title: String {
        switch self {
        case .paperCut: "剪纸"
        case .bordered: "边框 · 随机适配"
        case .dusk: "边框 · 暮色渐变（固定）"
        case .original: "原图"
        }
    }
}

/// Per-side padding in exported image pixels. Nil preserves the adaptive sizing.
public struct ShareBorderSize: Equatable, Sendable {
    public static let pixelRange = 8...300
    public static let automatic = ShareBorderSize()
    public let pixels: Int?

    public init(pixels: Int? = nil) {
        self.pixels = pixels.map { min(Self.pixelRange.upperBound, max(Self.pixelRange.lowerBound, $0)) }
    }

    public func padding(width: Int, height: Int) -> Int {
        pixels ?? min(120, max(24, Int((Double(min(width, height)) * 0.1).rounded())))
    }
}

public final class ShareBorderSizeStore {
    private let defaults: UserDefaults
    private let key = "PinSnip.ShareBorderSize.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ShareBorderSize {
        guard let value = defaults.object(forKey: key) as? Int else { return .automatic }
        return ShareBorderSize(pixels: value)
    }

    public func save(_ size: ShareBorderSize) {
        if let pixels = size.pixels {
            defaults.set(pixels, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public final class ShareStyleStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "PinSnip.ShareStyle.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ShareStyle {
        guard let rawValue = defaults.string(forKey: key) else { return .paperCut }
        return ShareStyle(rawValue: rawValue) ?? .paperCut
    }

    public func save(_ style: ShareStyle) {
        defaults.set(style.rawValue, forKey: key)
    }
}
