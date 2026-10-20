import Foundation

/// Visibility shared by automatic retraction and the capture lifecycle.
public struct ShelfVisibilityState: Equatable, Sendable {
    public private(set) var isRevealed = false
    public private(set) var isHeldForCapture = false

    public init() {}

    public mutating func setRevealed(_ revealed: Bool) {
        isRevealed = revealed
        if !revealed { isHeldForCapture = false }
    }

    public mutating func automaticallyHide() {
        guard !isHeldForCapture else { return }
        isRevealed = false
    }

    public mutating func beginCapture() {
        isHeldForCapture = isRevealed
    }

    public mutating func endCapture() {
        isHeldForCapture = false
    }
}
