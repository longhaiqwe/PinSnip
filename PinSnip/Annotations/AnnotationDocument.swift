import Foundation

public struct AnnotationDocument: Equatable, Sendable {
    public private(set) var annotations: [Annotation]
    private var undoStack: [[Annotation]]
    private var redoStack: [[Annotation]]

    public init(annotations: [Annotation] = []) {
        self.annotations = annotations
        self.undoStack = []
        self.redoStack = []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var nextSequenceNumber: Int {
        let greatestNumber = annotations.reduce(into: 0) { result, annotation in
            if case let .number(_, value, _, _) = annotation {
                result = max(result, value)
            }
        }
        return greatestNumber + 1
    }

    public mutating func append(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
    }

    @discardableResult
    public mutating func replace(at index: Int, with annotation: Annotation) -> Bool {
        guard annotations.indices.contains(index), annotations[index] != annotation else {
            return false
        }
        checkpoint()
        annotations[index] = annotation
        return true
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard annotations.indices.contains(index) else { return false }
        checkpoint()
        annotations.remove(at: index)
        return true
    }

    public mutating func clear() {
        guard !annotations.isEmpty else { return }
        checkpoint()
        annotations.removeAll()
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private mutating func checkpoint() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}
