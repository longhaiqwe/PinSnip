import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationDocumentTests: XCTestCase {
    func testUndoAndRedoMoveAnnotationsBetweenStacks() {
        var document = AnnotationDocument()
        document.append(
            .rectangle(
                CGRect(x: 1, y: 2, width: 30, height: 40),
                RGBAColor(red: 1, green: 0, blue: 0),
                3
            )
        )

        document.undo()
        XCTAssertTrue(document.annotations.isEmpty)

        document.redo()
        XCTAssertEqual(document.annotations.count, 1)
    }

    func testAppendingAfterUndoDiscardsRedoHistory() {
        var document = AnnotationDocument()
        document.append(.pencil([CGPoint(x: 1, y: 1)], .black, 2))
        document.undo()
        document.append(.arrow(from: .zero, to: CGPoint(x: 10, y: 10), .white, 4))

        document.redo()

        XCTAssertEqual(document.annotations.count, 1)
        guard case .arrow = document.annotations[0] else {
            return XCTFail("Expected the replacement arrow to remain")
        }
    }

    func testClearCanBeUndoneAsOneOperation() {
        var document = AnnotationDocument()
        document.append(.rectangle(CGRect(x: 1, y: 2, width: 3, height: 4), .black, 1))
        document.append(.pencil([.zero, CGPoint(x: 2, y: 2)], .white, 2))

        document.clear()
        XCTAssertTrue(document.annotations.isEmpty)

        document.undo()
        XCTAssertEqual(document.annotations.count, 2)
    }
}
