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

    func testSequenceNumbersStartAtOneAndReuseAnUndoneTail() {
        var document = AnnotationDocument()
        XCTAssertEqual(document.nextSequenceNumber, 1)

        document.append(
            .number(
                center: CGPoint(x: 10, y: 10),
                value: document.nextSequenceNumber,
                color: .black,
                diameter: 28
            )
        )
        XCTAssertEqual(document.nextSequenceNumber, 2)

        document.undo()
        XCTAssertEqual(document.nextSequenceNumber, 1)

        document.redo()
        XCTAssertEqual(document.nextSequenceNumber, 2)
    }

    func testReplacingTextBoxIsOneUndoableOperation() {
        let original = Annotation.text(
            rect: CGRect(x: 10, y: 12, width: 120, height: 30),
            text: "一段文字",
            color: .black,
            fontSize: 20
        )
        let resized = Annotation.text(
            rect: CGRect(x: 10, y: 12, width: 64, height: 56),
            text: "一段文字",
            color: .white,
            fontSize: 20
        )
        var document = AnnotationDocument(annotations: [original])

        XCTAssertTrue(document.replace(at: 0, with: resized))
        XCTAssertEqual(document.annotations, [resized])

        document.undo()
        XCTAssertEqual(document.annotations, [original])
    }

    func testRemovingEditedTextIsOneUndoableOperation() {
        let text = Annotation.text(
            rect: CGRect(x: 10, y: 12, width: 120, height: 30),
            text: "删除我",
            color: .black,
            fontSize: 20
        )
        var document = AnnotationDocument(annotations: [text])

        XCTAssertTrue(document.remove(at: 0))
        XCTAssertTrue(document.annotations.isEmpty)

        document.undo()
        XCTAssertEqual(document.annotations, [text])
    }
}
