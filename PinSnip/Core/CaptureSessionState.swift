import Foundation

public struct CaptureSessionState: Sendable {
    private var currentID: UUID?

    public init() {}

    public mutating func begin() -> UUID? {
        guard currentID == nil else { return nil }
        let id = UUID()
        currentID = id
        return id
    }

    public func isCurrent(_ id: UUID) -> Bool {
        currentID == id
    }

    @discardableResult
    public mutating func end(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }

    public mutating func endCurrent() {
        currentID = nil
    }
}
