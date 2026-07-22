import XCTest
@testable import PinSnipCore

final class CaptureSessionStateTests: XCTestCase {
    func testEndingTimedOutSessionAllowsRetryAndRejectsLateCompletion() throws {
        var state = CaptureSessionState()
        let timedOutSession = try XCTUnwrap(state.begin())

        XCTAssertNil(state.begin())
        XCTAssertTrue(state.end(timedOutSession))

        let retrySession = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.isCurrent(timedOutSession))
        XCTAssertFalse(state.end(timedOutSession))
        XCTAssertTrue(state.isCurrent(retrySession))
    }
}
