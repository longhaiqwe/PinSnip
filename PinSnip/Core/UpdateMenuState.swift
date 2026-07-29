import Foundation

public struct UpdateMenuState: Equatable, Sendable {
    public let automaticallyChecksForUpdates: Bool
    public let automaticallyDownloadsUpdates: Bool
    public let allowsAutomaticUpdates: Bool

    public init(
        automaticallyChecksForUpdates: Bool,
        automaticallyDownloadsUpdates: Bool,
        allowsAutomaticUpdates: Bool
    ) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        self.allowsAutomaticUpdates = allowsAutomaticUpdates
    }

    public var canToggleAutomaticDownloads: Bool {
        automaticallyChecksForUpdates && allowsAutomaticUpdates
    }
}
