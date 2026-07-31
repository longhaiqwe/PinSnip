import Foundation
import XCTest

final class StatusMenuIntegrationTests: XCTestCase {
    func testClickThroughRecoveryUsesExplicitMenuTitle() throws {
        let source = try source(at: "PinSnip/App/AppDelegate.swift")

        XCTAssertTrue(source.contains("关闭贴图鼠标穿透"))
        XCTAssertFalse(source.contains("恢复鼠标操作"))
    }

    func testClickThroughRecoveryIsDisabledUntilAPinNeedsIt() throws {
        let appDelegate = try source(at: "PinSnip/App/AppDelegate.swift")
        let manager = try source(at: "PinSnip/Pins/PinWindowManager.swift")
        let controller = try source(at: "PinSnip/Pins/PinWindowController.swift")

        XCTAssertTrue(appDelegate.contains("NSMenuItemValidation"))
        XCTAssertTrue(appDelegate.contains("menuItem.action == #selector(restoreInteraction)"))
        XCTAssertTrue(appDelegate.contains("return pinManager.hasClickThroughPins"))
        XCTAssertTrue(manager.contains("var hasClickThroughPins: Bool"))
        XCTAssertTrue(manager.contains("controllers.contains { $0.isClickThroughEnabled }"))
        XCTAssertTrue(controller.contains("var isClickThroughEnabled: Bool"))
        XCTAssertTrue(controller.contains("window?.ignoresMouseEvents == true"))
    }

    private func source(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
