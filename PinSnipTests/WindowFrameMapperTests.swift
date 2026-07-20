import CoreGraphics
import XCTest
@testable import PinSnipCore

final class WindowFrameMapperTests: XCTestCase {
    func testMapsQuartzFrameIntoRightHandScreenCoordinates() {
        let frame = WindowFrameMapper.localFrame(
            quartzFrame: CGRect(x: 1_500, y: 100, width: 400, height: 300),
            primaryScreenMaxY: 1_080,
            screenFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
        )

        XCTAssertEqual(frame, CGRect(x: 60, y: 680, width: 400, height: 300))
    }

    func testMapsQuartzFrameIntoScreenAbovePrimaryDisplay() {
        let frame = WindowFrameMapper.localFrame(
            quartzFrame: CGRect(x: 100, y: -500, width: 400, height: 400),
            primaryScreenMaxY: 1_080,
            screenFrame: CGRect(x: 0, y: 1_080, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 100, width: 400, height: 400))
    }

    func testClipsWindowToVisiblePartOfCurrentScreen() {
        let frame = WindowFrameMapper.localFrame(
            quartzFrame: CGRect(x: 1_300, y: 100, width: 300, height: 300),
            primaryScreenMaxY: 1_080,
            screenFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 680, width: 160, height: 300))
    }
}
