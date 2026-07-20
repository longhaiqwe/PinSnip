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

    public mutating func append(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
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
