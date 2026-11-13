import AppKit
import PinSnipCore
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
        XCTAssertTrue(source.contains("CaptureOutputService.copyScrollingCapture(image, style: shareStyle, borderSize: borderSize)"))
        let savedCapturePattern = #"case \.save:\s+let savedImage = CaptureOutputService\.render\(image, style: shareStyle, borderSize: borderSize\)[\s\S]*?let isOnShelf = rememberCapturedScreenshot\(savedImage\)\s+let result = CaptureOutputService\.saveRenderedResult\(savedImage,"#
        XCTAssertEqual(source.matches(of: savedCapturePattern), 2,
                       "Both save paths must preserve the styled result before presenting a cancellable save panel")
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

    func testPinnedContentSavesWithoutApplyingStyleAgain() throws {
        let source = try source(at: "PinSnip/Pins/PinWindowController.swift")
        XCTAssertTrue(source.contains("CaptureOutputService.saveRendered(image)"))
    }

    @MainActor
    func testOrdinaryAndScrollingCopyProduceIdenticalStyledPixels() throws {
        let image = try testImage()
        let ordinaryBoard = NSPasteboard.withUniqueName()
        let scrollingBoard = NSPasteboard.withUniqueName()
        defer {
            ordinaryBoard.releaseGlobally()
            scrollingBoard.releaseGlobally()
        }
        for style in ShareStyle.allCases {
            let border = ShareBorderSize(pixels: 24)
            let expected = CaptureOutputService.render(image, style: style, borderSize: border)
            let ordinary = CaptureOutputService.copy(image, style: style, borderSize: border, to: ordinaryBoard)
            let scrolling = CaptureOutputService.copyScrollingCapture(image, style: style, borderSize: border, to: scrollingBoard)
            let expectedPNG = try XCTUnwrap(NSBitmapImageRep(cgImage: expected).representation(using: .png, properties: [:]))
            XCTAssertEqual(ordinary.width, expected.width)
            XCTAssertEqual(scrolling.height, expected.height)
            XCTAssertEqual(ordinaryBoard.data(forType: .png), expectedPNG, "\(style)")
            XCTAssertEqual(scrollingBoard.data(forType: .png), expectedPNG, "\(style)")
        }
    }

    @MainActor
    func testPinnedContentCopiesItsExistingPixelsWithoutAddingAnotherBorder() throws {
        _ = NSApplication.shared
        let image = CaptureOutputService.render(try testImage(), style: .dusk, borderSize: ShareBorderSize(pixels: 24))
        let pin = PinWindowController(image: image, frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            pin.close()
            pasteboard.releaseGlobally()
        }
        var copied = false
        pin.copyOriginal(to: pasteboard) { copied = $0 }
        XCTAssertTrue(copied)
        let expectedPNG = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        XCTAssertEqual(pasteboard.data(forType: .png), expectedPNG)
    }

    private func testImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 24, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        return try XCTUnwrap(context.makeImage())
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
