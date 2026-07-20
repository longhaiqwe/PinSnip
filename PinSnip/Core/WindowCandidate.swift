import CoreGraphics

public struct WindowCandidate: Equatable, Sendable {
    public let id: CGWindowID
    public let frame: CGRect
    public let zOrder: Int

    public init(id: CGWindowID, frame: CGRect, zOrder: Int = 0) {
        self.id = id
        self.frame = frame
        self.zOrder = zOrder
    }

    public static func best(at point: CGPoint, in candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates
            .filter { $0.frame.contains(point) }
            .min { lhs, rhs in
                if lhs.zOrder != rhs.zOrder { return lhs.zOrder < rhs.zOrder }
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                if lhsArea == rhsArea { return lhs.id < rhs.id }
                return lhsArea < rhsArea
            }
    }
}
