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

    func testCopiedStillCaptureRecordsTheRenderedClipboardImageForF4() throws {
        let source = try captureCoordinatorSource()

        XCTAssertNotNil(
            source.range(
                of: #"case \.copy:\s+let copiedImage = CaptureOutputService\.copy\(image, style: shareStyle\)\s+rememberCapturedScreenshot\(copiedImage\)"#,
                options: .regularExpression
            )
        )
    }

    func testCopiedScrollingCaptureRecordsTheRenderedClipboardImageForF4() throws {
        let source = try captureCoordinatorSource()

        XCTAssertNotNil(
            source.range(
                of: #"case \.copy:\s+let copiedImage = CaptureOutputService\.copyScrollingCapture\(image, style: shareStyle\)\s+rememberCapturedScreenshot\(copiedImage\)"#,
                options: .regularExpression
            )
        )
    }

    private func captureCoordinatorSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PinSnip/Capture/CaptureCoordinator.swift"
            ),
            encoding: .utf8
        )
    }
}
