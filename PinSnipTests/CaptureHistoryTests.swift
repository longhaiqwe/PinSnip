import XCTest
@testable import PinSnipCore

final class CaptureHistoryTests: XCTestCase {
    func testReturnsCapturedScreenshotsNewestFirstWithoutRepeatingTheLatest() {
        var history = CaptureHistory<Int>()
        history.record(1)
        history.record(2)
        history.record(3)

        XCTAssertEqual(history.nextForPasting(), 3)
        XCTAssertEqual(history.nextForPasting(), 2)
        XCTAssertEqual(history.nextForPasting(), 1)
        XCTAssertNil(history.nextForPasting())
    }

    func testKeepsOnlyTheNewestEntriesWithinItsLimit() {
        var history = CaptureHistory<Int>(limit: 3)
        history.record(1)
        history.record(2)
        history.record(3)
        history.record(4)

        XCTAssertEqual(history.nextForPasting(), 4)
        XCTAssertEqual(history.nextForPasting(), 3)
        XCTAssertEqual(history.nextForPasting(), 2)
        XCTAssertNil(history.nextForPasting())
    }

    func testNewCaptureRestartsPastingFromTheNewestScreenshot() {
        var history = CaptureHistory<Int>()
        history.record(1)
        history.record(2)
        XCTAssertEqual(history.nextForPasting(), 2)

        history.record(3)

        XCTAssertEqual(history.nextForPasting(), 3)
        XCTAssertEqual(history.nextForPasting(), 2)
        XCTAssertEqual(history.nextForPasting(), 1)
    }
}
