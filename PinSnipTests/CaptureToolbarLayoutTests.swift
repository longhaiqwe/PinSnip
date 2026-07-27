import XCTest
@testable import PinSnipCore

final class CaptureToolbarLayoutTests: XCTestCase {
    func testToolbarBackgroundUsesADeeperNeutralGray() {
        XCTAssertEqual(
            CaptureToolbarStyle.backgroundColor,
            RGBAColor(red: 0.90, green: 0.90, blue: 0.90)
        )
    }

    func testToolbarUsesLightControlsForDarkIconsOnLightBackground() {
        XCTAssertTrue(CaptureToolbarStyle.usesLightControls)
    }

    func testStillImageActionsIncludeScrollingCaptureAndPutCopyAtTheFarRight() {
        XCTAssertEqual(
            CaptureToolbarLayout.stillImageTrailingActions,
            [.scrollCapture, .save, .pin, .cancel, .copy]
        )
    }

    func testGIFActionsPutThePrimaryRecordActionAtTheFarRight() {
        XCTAssertEqual(
            CaptureToolbarLayout.animatedGIFActions,
            [.cancel, .recordGIF]
        )
    }

    func testScrollingCaptureActionsPutStartAtTheFarRight() {
        XCTAssertEqual(
            CaptureToolbarLayout.scrollingCaptureActions,
            [.cancel, .scrollCapture]
        )
    }
}
