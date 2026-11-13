import Foundation

public enum ShareStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case bordered
    case dusk
    case ocean
    case lavender
    case peach
    case mint
    case rose
    case graphite
    case original

    public var title: String {
        switch self {
        case .bordered: "渐变 · 自动配色"
        case .dusk: "渐变 · 暮色"
        case .ocean: "渐变 · 海蓝"
        case .lavender: "渐变 · 薰衣草"
        case .peach: "渐变 · 蜜桃"
        case .mint: "渐变 · 薄荷"
        case .rose: "渐变 · 玫瑰"
        case .graphite: "渐变 · 石墨"
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
        guard let rawValue = defaults.string(forKey: key) else { return .dusk }
        return ShareStyle(rawValue: rawValue) ?? .dusk
    }

    public func save(_ style: ShareStyle) {
        defaults.set(style.rawValue, forKey: key)
    }
}
