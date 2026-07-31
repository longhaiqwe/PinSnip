import Foundation

public enum ShareStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case paperCut
    case bordered
    case original

    public var title: String {
        switch self {
        case .paperCut: "剪纸"
        case .bordered: "边框"
        case .original: "原图"
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
