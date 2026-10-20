import XCTest
@testable import PinSnipCore

final class ShelfVisibilityTests: XCTestCase {
    func testVisibleTopShelfSurvivesPointerLeavingForRecordingButton() {
        var state = ShelfVisibilityState()
        state.setRevealed(true)
        state.beginCapture()

        // The selection overlay freezes the image, while the live shelf's
        // mouse timer continues firing as the pointer moves to the toolbar.
        for _ in 0..<60 { state.automaticallyHide() }
        XCTAssertTrue(state.isRevealed)

        // Switching from selection to live GIF recording keeps the same hold.
        state.automaticallyHide()
        XCTAssertTrue(state.isRevealed)
    }

    func testFinishingOrCancellingCaptureRestoresAutoHide() {
        var state = ShelfVisibilityState()
        state.setRevealed(true)
        state.beginCapture()
        state.endCapture()
        XCTAssertTrue(state.isRevealed, "Releasing a hold must not abruptly hide the shelf")
        state.automaticallyHide()
        XCTAssertFalse(state.isRevealed)
    }

    func testCaptureDoesNotRevealAnInitiallyHiddenShelf() {
        var state = ShelfVisibilityState()
        state.beginCapture()
        XCTAssertFalse(state.isRevealed)
        state.setRevealed(true)
        state.automaticallyHide()
        XCTAssertFalse(state.isRevealed, "An initially hidden shelf keeps its normal hover behavior")
    }

    func testNormalRetractionAndExplicitHidingStillWork() {
        var state = ShelfVisibilityState()
        state.setRevealed(true)
        state.automaticallyHide()
        XCTAssertFalse(state.isRevealed)
        state.setRevealed(true)
        state.beginCapture()
        state.setRevealed(false)
        XCTAssertFalse(state.isRevealed)
    }
}
