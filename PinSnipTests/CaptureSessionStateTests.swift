import XCTest
@testable import PinSnipCore

final class CaptureSessionStateTests: XCTestCase {
    func testTimeoutDoesNotAdmitAnotherRequestWhileSystemIsStillWorking() throws {
        var state = CaptureSessionState()
        let session = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.end(session))

        XCTAssertNil(state.begin(), "Ending UI waiting must not enqueue another system capture")
    }

    func testSystemCompletionAfterTimeoutAllowsRetryAndRejectsLateCompletion() throws {
        var state = CaptureSessionState()
        let timedOutSession = try XCTUnwrap(state.begin())

        XCTAssertNil(state.begin())
        XCTAssertTrue(state.end(timedOutSession))
        state.captureFinished(timedOutSession)

        let retrySession = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.isCurrent(timedOutSession))
        XCTAssertFalse(state.end(timedOutSession))
        XCTAssertTrue(state.isCurrent(retrySession))
        state.captureFinished(timedOutSession)
        state.end(retrySession)
        XCTAssertNil(state.begin(), "A stale callback must not release the new request")
    }

    func testCancellationKeepsRequestSlotUntilCaptureFinishes() throws {
        var state = CaptureSessionState()
        let session = try XCTUnwrap(state.begin())
        state.endCurrent()
        XCTAssertNil(state.begin())
        state.captureFinished(session)
        XCTAssertNotNil(state.begin())
    }

    func testSuccessfulCaptureKeepsOverlaySessionActive() throws {
        var state = CaptureSessionState()
        let session = try XCTUnwrap(state.begin())
        state.captureFinished(session)
        XCTAssertTrue(state.isCurrent(session))
        XCTAssertNil(state.begin())
        state.end(session)
        XCTAssertNotNil(state.begin())
    }
}
