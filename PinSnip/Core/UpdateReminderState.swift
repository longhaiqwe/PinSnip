public struct UpdateReminderState: Equatable, Sendable {
    public let availableVersion: String?

    public init(availableVersion: String?) {
        self.availableVersion = availableVersion
    }

    public var statusSymbolName: String {
        availableVersion == nil ? "rectangle.on.rectangle.angled" : "arrow.down.circle"
    }

    public var updateActionTitle: String {
        guard let availableVersion else { return "检查更新…" }
        return "安装 PinSnip \(availableVersion)…"
    }
}
