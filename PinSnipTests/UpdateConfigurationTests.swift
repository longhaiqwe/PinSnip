import Foundation
import XCTest

final class UpdateConfigurationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testInfoPlistConfiguresSecureAutomaticUpdates() throws {
        let infoPlistURL = repositoryRoot.appendingPathComponent("PinSnip/Resources/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["SUFeedURL"] as? String,
            "https://raw.githubusercontent.com/longhaiqwe/PinSnip/main/appcast.xml"
        )
        let publicKey = try XCTUnwrap(plist["SUPublicEDKey"] as? String)
        XCTAssertEqual(Data(base64Encoded: publicKey)?.count, 32)
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(plist["SUScheduledCheckInterval"] as? Int, 86_400)
    }

    func testProjectPinsSparkleAndLinksItOnlyToTheAppTarget() throws {
        let projectSpec = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(projectSpec.contains("url: https://github.com/sparkle-project/Sparkle"))
        XCTAssertTrue(projectSpec.contains("exactVersion: 2.9.2"))
        XCTAssertTrue(projectSpec.contains("- package: Sparkle"))
    }

    func testRepositoryContainsAppcastAndGenerationScript() {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("appcast.xml").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("scripts/generate-appcast.sh").path
            )
        )
    }

    func testBootstrapAppcastPublishesCurrentVersionWithoutAnUnsignedDownload() throws {
        let appcast = try String(
            contentsOf: repositoryRoot.appendingPathComponent("appcast.xml"),
            encoding: .utf8
        )

        XCTAssertTrue(appcast.contains("<item>"))
        XCTAssertTrue(appcast.contains("<sparkle:version>5</sparkle:version>"))
        XCTAssertTrue(
            appcast.contains(
                "<sparkle:shortVersionString>0.4.0</sparkle:shortVersionString>"
            )
        )
        XCTAssertTrue(
            appcast.contains(
                "<link>https://github.com/longhaiqwe/PinSnip/releases/tag/v0.4.0</link>"
            )
        )
    }
}
