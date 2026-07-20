import CoreGraphics
import XCTest
@testable import PinSnipCore

final class LastCaptureRegionTests: XCTestCase {
    func testNormalizedRegionRoundTripsOnDifferentScreenSize() {
        let region = LastCaptureRegion(
            rect: CGRect(x: 100, y: 50, width: 400, height: 200),
            screenSize: CGSize(width: 1000, height: 500)
        )

        XCTAssertEqual(
            region.rect(in: CGSize(width: 2000, height: 1000)),
            CGRect(x: 200, y: 100, width: 800, height: 400)
        )
    }
}
