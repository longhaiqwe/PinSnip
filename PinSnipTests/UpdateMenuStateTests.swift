import XCTest
@testable import PinSnipCore

final class UpdateMenuStateTests: XCTestCase {
    func testAutomaticDownloadControlRequiresAutomaticChecksAndFrameworkPermission() {
        XCTAssertFalse(
            UpdateMenuState(
                automaticallyChecksForUpdates: false,
                automaticallyDownloadsUpdates: false,
                allowsAutomaticUpdates: true
            ).canToggleAutomaticDownloads
        )

        XCTAssertFalse(
            UpdateMenuState(
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: false,
                allowsAutomaticUpdates: false
            ).canToggleAutomaticDownloads
        )

        XCTAssertTrue(
            UpdateMenuState(
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: false,
                allowsAutomaticUpdates: true
            ).canToggleAutomaticDownloads
        )
    }
}
