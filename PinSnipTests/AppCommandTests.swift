import XCTest
@testable import PinSnipCore

@MainActor
final class AppCommandTests: XCTestCase {
    func testRoutesCaptureLastRegionAndPasteInOrder() {
        var received: [AppCommand] = []
        let router = AppCommandRouter { received.append($0) }

        router.perform(.capture)
        router.perform(.captureLastRegion)
        router.perform(.paste)

        XCTAssertEqual(received, [.capture, .captureLastRegion, .paste])
    }

    func testDisabledRouterIgnoresCommandsUntilEnabled() {
        var received: [AppCommand] = []
        let router = AppCommandRouter(isEnabled: false) { received.append($0) }

        router.perform(.capture)
        router.isEnabled = true
        router.perform(.capture)

        XCTAssertEqual(received, [.capture])
    }
}
