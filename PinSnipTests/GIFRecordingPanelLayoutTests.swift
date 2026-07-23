import CoreGraphics
import XCTest
@testable import PinSnipCore

final class GIFRecordingPanelLayoutTests: XCTestCase {
    func testRecordingPanelRemainsVisibleWhileMenuBarAppIsInactive() {
        XCTAssertFalse(GIFRecordingPanelLayout.hidesOnDeactivate)
    }

    func testRecordingBorderUsesTheSameBlueAsTheSelectionBorder() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.recordingBorderColor,
            SelectionOverlayStyle.selectionBorderColor
        )
    }

    func testContentWidthIncludesBothOutputActionsSpacingAndPadding() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.minimumContentWidth(
                statusWidth: 145,
                outputButtonWidths: [113, 121],
                spacing: 14,
                horizontalPadding: 12
            ),
            431
        )
    }

    func testRecordingBorderSitsOutsideTheCapturedSelectionOnAnOffsetScreen() {
        let layout = GIFRecordingBorderLayout(
            screenFrame: CGRect(x: 1_440, y: -200, width: 1_920, height: 1_080),
            selectionRect: CGRect(x: 100, y: 80, width: 640, height: 360),
            lineWidth: 3
        )

        XCTAssertEqual(
            layout.windowFrame,
            CGRect(x: 1_537, y: -123, width: 646, height: 366)
        )
        XCTAssertEqual(
            layout.captureRect,
            CGRect(x: 3, y: 3, width: 640, height: 360)
        )
        XCTAssertEqual(
            layout.borderRect,
            CGRect(x: 1.5, y: 1.5, width: 643, height: 363)
        )
        XCTAssertEqual(
            layout.borderRect.insetBy(dx: 1.5, dy: 1.5),
            layout.captureRect
        )
    }
}
