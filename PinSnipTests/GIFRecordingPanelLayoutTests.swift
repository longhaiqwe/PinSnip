import CoreGraphics
import XCTest
@testable import PinSnipCore

final class GIFRecordingPanelLayoutTests: XCTestCase {
    func testRecordingPanelUsesTheSameCompactTitlelessHUDStyle() {
        XCTAssertFalse(GIFRecordingPanelLayout.usesTitleBar)
        XCTAssertLessThanOrEqual(GIFRecordingPanelLayout.contentSize.width, 420)
        XCTAssertEqual(
            GIFRecordingPanelLayout.contentSize.height,
            ScrollingCapturePanelLayout.contentSize.height
        )
        XCTAssertEqual(
            GIFRecordingPanelLayout.cornerRadius,
            ScrollingCapturePanelLayout.cornerRadius
        )
    }

    func testRecordingPanelRemainsVisibleWhileMenuBarAppIsInactive() {
        XCTAssertFalse(GIFRecordingPanelLayout.hidesOnDeactivate)
    }

    func testRecordingBorderUsesTheSameBlueAsTheSelectionBorder() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.recordingBorderColor,
            SelectionOverlayStyle.selectionBorderColor
        )
    }

    func testRecordingProgressTextIsConciseAndUsesMonospacedTimes() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.progressText(
                elapsedSeconds: 4,
                maximumSeconds: 30
            ),
            "录制中 · 00:04 / 00:30"
        )
    }

    func testRecordingPanelCentersAboveSelectionWhenSpaceIsAvailable() {
        XCTAssertEqual(
            GIFRecordingPanelLayout.panelFrame(
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 860),
                selectionFrame: CGRect(x: 200, y: 100, width: 800, height: 600)
            ),
            CGRect(x: 400, y: 712, width: 400, height: 50)
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
