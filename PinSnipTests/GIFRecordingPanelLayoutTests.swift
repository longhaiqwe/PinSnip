import CoreGraphics
import XCTest
@testable import PinSnipCore

final class GIFRecordingPanelLayoutTests: XCTestCase {
    func testContentWidthIncludesBothControlsSpacingAndPadding() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.minimumContentWidth(
                statusWidth: 145,
                stopButtonWidth: 113,
                spacing: 14,
                horizontalPadding: 12
            ),
            296
        )
    }

    func testRecordingBorderMatchesSelectionOnAnOffsetScreen() {
        let layout = GIFRecordingBorderLayout(
            screenFrame: CGRect(x: 1_440, y: -200, width: 1_920, height: 1_080),
            selectionRect: CGRect(x: 100, y: 80, width: 640, height: 360),
            lineWidth: 3
        )

        XCTAssertEqual(
            layout.windowFrame,
            CGRect(x: 1_540, y: -120, width: 640, height: 360)
        )
        XCTAssertEqual(
            layout.borderRect,
            CGRect(x: 1.5, y: 1.5, width: 637, height: 357)
        )
    }
}
