import Foundation

public struct AnimationPlaybackState: Equatable, Sendable {
    private let frameCount: Int
    public private(set) var frameIndex = 0

    public init(frameCount: Int) {
        self.frameCount = max(1, frameCount)
    }

    @discardableResult
    public mutating func advance() -> Int {
        frameIndex = (frameIndex + 1) % frameCount
        return frameIndex
    }
}
