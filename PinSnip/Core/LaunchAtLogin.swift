import Foundation

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case notSupported
}

public protocol LaunchAtLoginServicing: AnyObject, Sendable {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
public final class LaunchAtLoginManager {
    private let service: LaunchAtLoginServicing

    public init(service: LaunchAtLoginServicing) {
        self.service = service
    }

    public var isEnabled: Bool {
        service.status == .enabled
    }

    public var status: LaunchAtLoginStatus {
        service.status
    }

    @discardableResult
    public func toggle() throws -> LaunchAtLoginStatus {
        if isEnabled {
            try service.unregister()
        } else {
            try service.register()
        }
        return service.status
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
