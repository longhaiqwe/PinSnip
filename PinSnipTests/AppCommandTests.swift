import XCTest
@testable import PinSnipCore

@MainActor
final class AppCommandTests: XCTestCase {
    func testRoutesCaptureRecordingLastRegionAndPasteInOrder() {
        var received: [AppCommand] = []
        let router = AppCommandRouter { received.append($0) }

        router.perform(.capture)
        router.perform(.recordAnimatedGIF)
        router.perform(.captureLastRegion)
        router.perform(.paste)

        XCTAssertEqual(received, [.capture, .recordAnimatedGIF, .captureLastRegion, .paste])
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
