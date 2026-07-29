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

    public static func stableCandidates(
        before: [WindowCandidate],
        after: [WindowCandidate],
        tolerance: CGFloat = 0.5
    ) -> [WindowCandidate] {
        let previousCandidates = Dictionary(
            uniqueKeysWithValues: before.map { ($0.id, $0) }
        )
        return after.filter { candidate in
            guard let previous = previousCandidates[candidate.id],
                  previous.kind == candidate.kind
            else { return false }
            return abs(previous.frame.minX - candidate.frame.minX) <= tolerance
                && abs(previous.frame.minY - candidate.frame.minY) <= tolerance
                && abs(previous.frame.width - candidate.frame.width) <= tolerance
                && abs(previous.frame.height - candidate.frame.height) <= tolerance
        }
    }

    public static func requiresRecapture(
        at point: CGPoint,
        before: [WindowCandidate],
        after: [WindowCandidate],
        tolerance: CGFloat = 0.5
    ) -> Bool {
        let previous = best(at: point, in: before)
        let current = best(at: point, in: after)
        guard previous?.id == current?.id else { return true }
        guard let current else { return false }
        return !stableCandidates(
            before: before,
            after: after,
            tolerance: tolerance
        ).contains(where: { $0.id == current.id })
    }
}
