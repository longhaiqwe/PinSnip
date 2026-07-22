import Foundation
import XCTest

final class AppIconConfigurationTests: XCTestCase {
    func testApplicationDeclaresBundledIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = repositoryRoot.appendingPathComponent("PinSnip/Resources")
        let infoData = try Data(contentsOf: resources.appendingPathComponent("Info.plist"))
        let propertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )

        XCTAssertEqual(propertyList["CFBundleIconFile"] as? String, "PinSnip.icns")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("PinSnip.icns").path
            )
        )

        let projectConfiguration = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(projectConfiguration.contains("buildPhase: resources"))
    }
}
