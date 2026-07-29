import CoreGraphics

public enum WindowCandidateKind: Int, Equatable, Sendable {
    case applicationWindow
    case visualRegion
}

public struct WindowCandidate: Equatable, Sendable {
    public let id: CGWindowID
    public let frame: CGRect
    public let zOrder: Int
    public let kind: WindowCandidateKind

    public init(
        id: CGWindowID,
        frame: CGRect,
        zOrder: Int = 0,
        kind: WindowCandidateKind = .applicationWindow
    ) {
        self.id = id
        self.frame = frame
        self.zOrder = zOrder
        self.kind = kind
    }

    public static func best(at point: CGPoint, in candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates
            .filter { $0.frame.contains(point) }
            .min { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind == .visualRegion
                }
                if lhs.zOrder != rhs.zOrder { return lhs.zOrder < rhs.zOrder }
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                if lhsArea == rhsArea { return lhs.id < rhs.id }
                return lhsArea < rhsArea
            }
    }
}
