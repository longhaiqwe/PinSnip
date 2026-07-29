import XCTest
@testable import PinSnipCore

final class UpdateReminderStateTests: XCTestCase {
    func testAvailableVersionChangesTheStatusItemAndUpdateAction() {
        let idle = UpdateReminderState(availableVersion: nil)
        XCTAssertEqual(idle.statusSymbolName, "rectangle.on.rectangle.angled")
        XCTAssertEqual(idle.updateActionTitle, "检查更新…")

        let available = UpdateReminderState(availableVersion: "0.4.0")
        XCTAssertEqual(available.statusSymbolName, "arrow.down.circle")
        XCTAssertEqual(available.updateActionTitle, "安装 PinSnip 0.4.0…")
    }
}
