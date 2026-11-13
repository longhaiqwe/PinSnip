import Foundation

public struct CaptureSessionState: Sendable {
    private var currentID: UUID?
    private var pendingCaptureID: UUID?

    public init() {}

    public mutating func begin() -> UUID? {
        guard currentID == nil, pendingCaptureID == nil else { return nil }
        let id = UUID()
        currentID = id
        pendingCaptureID = id
        return id
    }

    /// A UI timeout/cancellation cannot cancel a request already sent to macOS.
    /// Keep its slot until the capture actually returns, discarding late pixels.
    public mutating func captureFinished(_ id: UUID) {
        guard pendingCaptureID == id else { return }
        pendingCaptureID = nil
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
