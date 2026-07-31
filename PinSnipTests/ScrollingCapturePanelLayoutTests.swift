import CoreGraphics
import XCTest
@testable import PinSnipCore

final class ScrollingCapturePanelLayoutTests: XCTestCase {
    func testControlPanelIsACompactTitlelessHUD() {
        XCTAssertFalse(ScrollingCapturePanelLayout.usesTitleBar)
        XCTAssertLessThanOrEqual(
            ScrollingCapturePanelLayout.contentSize.width,
            480
        )
        XCTAssertEqual(ScrollingCapturePanelLayout.contentSize.height, 50)
    }

    func testProgressTextKeepsModeAndMeasurementsConcise() {
        XCTAssertEqual(
            ScrollingCapturePanelLayout.progressText(
                isAutomatic: false,
                frameCount: 4,
                pixelHeight: 3_115
            ),
            "手动滚动 · 4 屏 · 3115 px"
        )
        XCTAssertEqual(
            ScrollingCapturePanelLayout.progressText(
                isAutomatic: true,
                frameCount: 4,
                pixelHeight: 3_115
            ),
            "自动滚动 · 4 屏 · 3115 px"
        )
    }

    func testControlPanelCentersAboveSelectionWhenSpaceIsAvailable() {
        XCTAssertEqual(
            ScrollingCapturePanelLayout.panelFrame(
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 860),
                selectionFrame: CGRect(x: 200, y: 100, width: 800, height: 600)
            ),
            CGRect(x: 370, y: 712, width: 460, height: 50)
        )
    }

    func testControlPanelMovesBelowSelectionAndStaysInsideVisibleScreen() {
        XCTAssertEqual(
            ScrollingCapturePanelLayout.panelFrame(
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 860),
                selectionFrame: CGRect(x: 1_300, y: 200, width: 100, height: 640)
            ),
            CGRect(x: 980, y: 138, width: 460, height: 50)
        )
    }
}
