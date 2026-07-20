public protocol ScreenCapturePermissionProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization() -> Bool
}

public final class ScreenCapturePermissionGate {
    private let provider: ScreenCapturePermissionProviding

    public init(provider: ScreenCapturePermissionProviding) {
        self.provider = provider
    }

    public func ensureAuthorized() -> Bool {
        if provider.isAuthorized {
            return true
        }
        return provider.requestAuthorization()
    }
}
