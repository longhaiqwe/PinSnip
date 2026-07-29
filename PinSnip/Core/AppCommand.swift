import Foundation

public enum AppCommand: Equatable, Sendable {
    case capture
    case captureScrolling
    case recordAnimatedGIF
    case captureLastRegion
    case paste
    case showAllPins
    case hideAllPins
    case checkForUpdates
    case toggleAutomaticUpdateChecks
    case toggleAutomaticUpdateDownloads
}

@MainActor
public final class AppCommandRouter {
    public typealias Handler = @MainActor (AppCommand) -> Void

    public var isEnabled: Bool
    private let handler: Handler

    public init(isEnabled: Bool = true, handler: @escaping Handler) {
        self.isEnabled = isEnabled
        self.handler = handler
    }

    public func perform(_ command: AppCommand) {
        guard isEnabled else { return }
        handler(command)
    }
}
