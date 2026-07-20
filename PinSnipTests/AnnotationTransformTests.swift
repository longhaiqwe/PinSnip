import CoreGraphics
import XCTest
@testable import PinSnipCore

final class AnnotationTransformTests: XCTestCase {
    func testMapsRectangleFromOverlayPointsIntoCropPixels() {
        let subject = Annotation.rectangle(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            .black,
            3
        )

        XCTAssertEqual(
            subject.mapped(relativeTo: CGPoint(x: 5, y: 6), scale: 2),
            .rectangle(CGRect(x: 10, y: 28, width: 60, height: 80), .black, 6)
        )
    }

    func testMapsArrowAndPencilPoints() {
        let arrow = Annotation.arrow(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 20, y: 40),
            .white,
            2
        )
        XCTAssertEqual(
            arrow.mapped(relativeTo: CGPoint(x: 10, y: 10), scale: 0.5),
            .arrow(from: CGPoint(x: 0, y: 5), to: CGPoint(x: 5, y: 15), .white, 1)
        )

        let pencil = Annotation.pencil([CGPoint(x: 3, y: 5), CGPoint(x: 4, y: 7)], .black, 4)
        XCTAssertEqual(
            pencil.mapped(relativeTo: CGPoint(x: 1, y: 2), scale: 2),
            .pencil([CGPoint(x: 4, y: 6), CGPoint(x: 6, y: 10)], .black, 8)
        )
    }
}
