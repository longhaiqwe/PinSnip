import XCTest
@testable import PinSnipCore

final class ScreenCapturePermissionGateTests: XCTestCase {
    func testAuthorizedProviderSkipsRequest() {
        let provider = PermissionProviderStub(isAuthorized: true, requestResult: false)
        let gate = ScreenCapturePermissionGate(provider: provider)

        XCTAssertTrue(gate.ensureAuthorized())
        XCTAssertEqual(provider.requestCount, 0)
    }

    func testUnauthorizedProviderRequestsAccessOnce() {
        let provider = PermissionProviderStub(isAuthorized: false, requestResult: true)
        let gate = ScreenCapturePermissionGate(provider: provider)

        XCTAssertTrue(gate.ensureAuthorized())
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testDeniedRequestStopsCapture() {
        let provider = PermissionProviderStub(isAuthorized: false, requestResult: false)
        let gate = ScreenCapturePermissionGate(provider: provider)

        XCTAssertFalse(gate.ensureAuthorized())
        XCTAssertEqual(provider.requestCount, 1)
    }
}

private final class PermissionProviderStub: ScreenCapturePermissionProviding {
    let isAuthorized: Bool
    let requestResult: Bool
    private(set) var requestCount = 0

    init(isAuthorized: Bool, requestResult: Bool) {
        self.isAuthorized = isAuthorized
        self.requestResult = requestResult
    }

    func requestAuthorization() -> Bool {
        requestCount += 1
        return requestResult
    }
}
