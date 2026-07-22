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
}
