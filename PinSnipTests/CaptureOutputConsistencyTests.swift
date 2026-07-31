import Foundation
import XCTest

final class CaptureOutputConsistencyTests: XCTestCase {
    func testScrollingCaptureDoesNotBypassSocialShareDecoration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PinSnip/Output/CaptureOutputService.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("decorates: false"))
    }
}
