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

    func testAppcastPublishesSignedVersionNoNewerThanSource() throws {
        let appcast = try String(
            contentsOf: repositoryRoot.appendingPathComponent("appcast.xml"),
            encoding: .utf8
        )
        let currentItem = try XCTUnwrap(
            appcast.components(separatedBy: "<item>").dropFirst().first?
                .components(separatedBy: "</item>").first
        )

        let version = try String(contentsOf: repositoryRoot.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let buildLine = try XCTUnwrap(project.split(separator: "\n").first { $0.contains("CURRENT_PROJECT_VERSION:") })
        let build = try XCTUnwrap(buildLine.split(separator: "\"").dropFirst().first.flatMap { Int($0) })
        let publishedBuild = try XCTUnwrap(
            appcastValue("sparkle:version", in: currentItem).flatMap { Int($0) }
        )
        let publishedVersion = try XCTUnwrap(appcastValue("sparkle:shortVersionString", in: currentItem))

        // Source can be one release ahead while its GitHub Release is a draft.
        XCTAssertLessThanOrEqual(publishedBuild, build)
        XCTAssertNotEqual(publishedVersion.compare(version, options: .numeric), .orderedDescending)
        XCTAssertEqual(publishedVersion == version, publishedBuild == build)
        XCTAssertTrue(
            currentItem.contains(
                "releases/download/v\(publishedVersion)/PinSnip-v\(publishedVersion)-macOS-universal.zip"
            )
        )
        XCTAssertTrue(currentItem.contains("sparkle:edSignature="))
    }

    private func appcastValue(_ tag: String, in item: String) -> String? {
        guard let start = item.range(of: "<\(tag)>")?.upperBound,
              let end = item[start...].range(of: "</\(tag)>")?.lowerBound,
              start < end else { return nil }
        return String(item[start..<end])
    }

    func testAppcastReleaseNotesLinkResolvesToPublishedRelease() throws {
        let appcast = try String(
            contentsOf: repositoryRoot.appendingPathComponent("appcast.xml"),
            encoding: .utf8
        )

        XCTAssertTrue(
            appcast.contains(
                "<sparkle:fullReleaseNotesLink>"
                    + "https://github.com/longhaiqwe/PinSnip/releases/tag/v0.8.1"
                    + "</sparkle:fullReleaseNotesLink>"
            )
        )
        XCTAssertFalse(
            appcast.contains(
                "raw.githubusercontent.com/longhaiqwe/PinSnip/main/"
                    + "PinSnip-v0.8.1-macOS-universal.md"
            )
        )
    }
}
