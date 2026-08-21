import CoreGraphics

public struct WindowSelectionState: Equatable, Sendable {
    public private(set) var rect = CGRect.zero

    private var candidates: [WindowCandidate]
    private var dragStart: CGPoint?
    private var pressedWindowCandidate: WindowCandidate?
    private var selectedWindowCandidate: WindowCandidate?
    private var isDragging = false

    public init(candidates: [WindowCandidate], initialRect: CGRect = .zero) {
        self.candidates = candidates
        rect = initialRect
    }

    public mutating func hover(at point: CGPoint) {
        guard dragStart == nil else { return }
        selectedWindowCandidate = WindowCandidate.best(at: point, in: candidates)
        rect = selectedWindowCandidate?.frame ?? .zero
    }

    public mutating func addCandidates(
        _ newCandidates: [WindowCandidate],
        hoveringAt point: CGPoint
    ) {
        candidates.append(contentsOf: newCandidates)
        hover(at: point)
    }

    public mutating func begin(at point: CGPoint) {
        dragStart = point
        pressedWindowCandidate = WindowCandidate.best(at: point, in: candidates)
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
            selectedWindowCandidate = pressedWindowCandidate
            rect = selectedWindowCandidate?.frame ?? .zero
        } else {
            selectedWindowCandidate = nil
        }

        dragStart = nil
        pressedWindowCandidate = nil
        isDragging = false

        guard rect.width >= minimumDimension, rect.height >= minimumDimension else {
            rect = .zero
            selectedWindowCandidate = nil
            return false
        }
        return true
    }

    public func selectedApplicationWindowID(
        matching selectionRect: CGRect,
        tolerance: CGFloat = 0.5
    ) -> CGWindowID? {
        guard let selectedWindowCandidate,
              selectedWindowCandidate.kind == .applicationWindow,
              abs(selectedWindowCandidate.frame.minX - selectionRect.minX) <= tolerance,
              abs(selectedWindowCandidate.frame.minY - selectionRect.minY) <= tolerance,
              abs(selectedWindowCandidate.frame.width - selectionRect.width) <= tolerance,
              abs(selectedWindowCandidate.frame.height - selectionRect.height) <= tolerance
        else { return nil }
        return selectedWindowCandidate.id
    }
}
