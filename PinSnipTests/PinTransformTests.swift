import XCTest
@testable import PinSnipCore

final class PinTransformTests: XCTestCase {
    func testOpacityAndScaleAreClamped() {
        XCTAssertEqual(PinTransform(opacity: 2, scale: 20).opacity, 1)
        XCTAssertEqual(PinTransform(opacity: -1, scale: 0).opacity, 0.15)
        XCTAssertEqual(PinTransform(opacity: 2, scale: 20).scale, 8)
        XCTAssertEqual(PinTransform(opacity: -1, scale: 0).scale, 0.1)
    }

    func testQuarterTurnsAreNormalized() {
        XCTAssertEqual(PinTransform(rotationQuarterTurns: 5).rotationQuarterTurns, 1)
        XCTAssertEqual(PinTransform(rotationQuarterTurns: -1).rotationQuarterTurns, 3)
    }

    func testOperationsReturnUpdatedTransforms() {
        let original = PinTransform()
        let transformed = original
            .rotatedClockwise()
            .togglingHorizontalFlip()
            .withOpacity(0.5)
            .zoomed(by: 2)

        XCTAssertEqual(transformed.rotationQuarterTurns, 1)
        XCTAssertTrue(transformed.isFlippedHorizontally)
        XCTAssertEqual(transformed.opacity, 0.5)
        XCTAssertEqual(transformed.scale, 2)
    }
}
