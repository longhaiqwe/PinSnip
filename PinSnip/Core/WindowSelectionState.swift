import CoreGraphics

public struct WindowSelectionState: Equatable, Sendable {
    public private(set) var rect = CGRect.zero

    private let candidates: [WindowCandidate]
    private var dragStart: CGPoint?
    private var pressedWindowRect: CGRect?
    private var isDragging = false

    public init(candidates: [WindowCandidate], initialRect: CGRect = .zero) {
        self.candidates = candidates
        rect = initialRect
    }

    public mutating func hover(at point: CGPoint) {
        guard dragStart == nil else { return }
        rect = WindowCandidate.best(at: point, in: candidates)?.frame ?? .zero
    }

    public mutating func begin(at point: CGPoint) {
        dragStart = point
        pressedWindowRect = WindowCandidate.best(at: point, in: candidates)?.frame
        isDragging = false
    }

    public mutating func drag(
        to point: CGPoint,
        inside bounds: CGRect,
        constraint: SelectionConstraint? = nil,
        activationDistance: CGFloat = 3
    ) {
        guard let dragStart else { return }
        if !isDragging {
            let distance = hypot(point.x - dragStart.x, point.y - dragStart.y)
            guard distance >= activationDistance else { return }
            isDragging = true
        }
        rect = constraint?.rect(from: dragStart, to: point, inside: bounds)
            ?? SelectionRect(start: dragStart, end: point).clamped(to: bounds).rect
    }

    @discardableResult
    public mutating func end(minimumDimension: CGFloat) -> Bool {
        if !isDragging {
            rect = pressedWindowRect ?? .zero
        }

        dragStart = nil
        pressedWindowRect = nil
        isDragging = false

        guard rect.width >= minimumDimension, rect.height >= minimumDimension else {
            rect = .zero
            return false
        }
        return true
    }
}
