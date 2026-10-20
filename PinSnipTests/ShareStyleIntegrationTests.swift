import Foundation
import XCTest

final class ShareStyleIntegrationTests: XCTestCase {
    func testStatusMenuOffersEveryStyleAndPersistsSelection() throws {
        let source = try source(at: "PinSnip/App/AppDelegate.swift")

        XCTAssertTrue(source.contains("ShareStyle.allCases"))
        XCTAssertTrue(source.contains("shareStyleStore.save(style)"))
        XCTAssertTrue(source.contains("captureCoordinator.updateShareStyle(style)"))
    }

    func testOrdinaryAndScrollingCaptureUseTheSameSelectedStyle() throws {
        let source = try source(at: "PinSnip/Capture/CaptureCoordinator.swift")

        XCTAssertTrue(source.contains("CaptureOutputService.copy(image, style: shareStyle, borderSize: borderSize)"))
        XCTAssertTrue(source.contains("CaptureOutputService.save(image, style: shareStyle, borderSize: borderSize)"))
        XCTAssertTrue(source.contains("CaptureOutputService.copyScrollingCapture(image, style: shareStyle, borderSize: borderSize)"))
        XCTAssertTrue(source.contains("CaptureOutputService.saveScrollingCapture(image, style: shareStyle, borderSize: borderSize)"))
    }

    func testStillAndScrollingPinsUseTheSelectedStyle() throws {
        let source = try source(at: "PinSnip/Capture/CaptureCoordinator.swift")
        let styledPinPattern = #"let pinnedImage = CaptureOutputService\.render\(image, style: shareStyle, borderSize: borderSize\)\s+pinManager\.pin\(pinnedImage\)"#

        XCTAssertEqual(
            source.matches(of: styledPinPattern),
            2,
            "ordinary and scrolling pins should both render exactly once"
        )
    }

    func testGIFRecordingUsesTheSelectedStyle() throws {
        let coordinator = try source(at: "PinSnip/Capture/CaptureCoordinator.swift")
        let recorder = try source(at: "PinSnip/Capture/ScreenGIFRecorder.swift")

        XCTAssertTrue(coordinator.contains("recorder.stop(style: shareStyle, borderSize: borderSize)"))
        XCTAssertTrue(recorder.contains("style: ShareStyle"))
        XCTAssertTrue(recorder.contains("style: style"))
    }

    func testPinnedContentCopiesAndSavesWithoutApplyingStyleAgain() throws {
        let source = try source(at: "PinSnip/Pins/PinWindowController.swift")

        XCTAssertTrue(source.contains("CaptureOutputService.copyRendered(image)"))
        XCTAssertTrue(source.contains("CaptureOutputService.saveRendered(image)"))
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

private extension String {
    func matches(of pattern: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(
            in: self,
            range: NSRange(startIndex..<endIndex, in: self)
        )
    }
}
