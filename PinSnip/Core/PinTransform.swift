import CoreGraphics

public struct PinTransform: Equatable, Sendable {
    public let rotationQuarterTurns: Int
    public let isFlippedHorizontally: Bool
    public let isFlippedVertically: Bool
    public let opacity: CGFloat
    public let scale: CGFloat

    public init(
        rotationQuarterTurns: Int = 0,
        isFlippedHorizontally: Bool = false,
        isFlippedVertically: Bool = false,
        opacity: CGFloat = 1,
        scale: CGFloat = 1
    ) {
        self.rotationQuarterTurns = ((rotationQuarterTurns % 4) + 4) % 4
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
        self.opacity = min(1, max(0.15, opacity))
        self.scale = min(8, max(0.1, scale))
    }

    public func rotatedClockwise() -> PinTransform {
        replacing(rotationQuarterTurns: rotationQuarterTurns + 1)
    }

    public func rotatedCounterclockwise() -> PinTransform {
        replacing(rotationQuarterTurns: rotationQuarterTurns - 1)
    }

    public func togglingHorizontalFlip() -> PinTransform {
        replacing(isFlippedHorizontally: !isFlippedHorizontally)
    }

    public func togglingVerticalFlip() -> PinTransform {
        replacing(isFlippedVertically: !isFlippedVertically)
    }

    public func withOpacity(_ opacity: CGFloat) -> PinTransform {
        replacing(opacity: opacity)
    }

    public func zoomed(by factor: CGFloat) -> PinTransform {
        replacing(scale: scale * factor)
    }

    private func replacing(
        rotationQuarterTurns: Int? = nil,
        isFlippedHorizontally: Bool? = nil,
        isFlippedVertically: Bool? = nil,
        opacity: CGFloat? = nil,
        scale: CGFloat? = nil
    ) -> PinTransform {
        PinTransform(
            rotationQuarterTurns: rotationQuarterTurns ?? self.rotationQuarterTurns,
            isFlippedHorizontally: isFlippedHorizontally ?? self.isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically ?? self.isFlippedVertically,
            opacity: opacity ?? self.opacity,
            scale: scale ?? self.scale
        )
    }
}
