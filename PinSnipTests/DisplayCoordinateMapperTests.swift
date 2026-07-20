import CoreGraphics
import XCTest
@testable import PinSnipCore

final class DisplayCoordinateMapperTests: XCTestCase {
    func testConvertsBottomLeftPointsToTopLeftRetinaPixels() {
        let mapper = DisplayCoordinateMapper(viewHeight: 500, pixelScale: 2)

        XCTAssertEqual(
            mapper.pixelRect(for: CGRect(x: 10, y: 20, width: 30, height: 40)),
            CGRect(x: 20, y: 880, width: 60, height: 80)
        )
    }

    func testRoundsOutwardToAvoidLosingEdgePixels() {
        let mapper = DisplayCoordinateMapper(viewHeight: 100, pixelScale: 1.5)

        XCTAssertEqual(
            mapper.pixelRect(for: CGRect(x: 0.2, y: 0.2, width: 10.2, height: 10.2)),
            CGRect(x: 0, y: 134, width: 16, height: 16)
        )
    }
}
