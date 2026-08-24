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

    func testExactWindowSelectionUsesTransparentWindowCapture() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let service = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PinSnip/Capture/ScreenCaptureService.swift"
            ),
            encoding: .utf8
        )
        let overlay = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PinSnip/Capture/SelectionOverlayView.swift"
            ),
            encoding: .utf8
        )
        let coordinator = try captureCoordinatorSource()

        XCTAssertTrue(service.contains("SCContentFilter(desktopIndependentWindow: window)"))
        XCTAssertTrue(service.contains("configuration.shouldBeOpaque = policy.shouldBeOpaque"))
        XCTAssertTrue(service.contains("configuration.ignoreShadowsSingleWindow = policy.ignoresShadow"))
        XCTAssertTrue(overlay.contains("selectedApplicationWindowID(matching: selectionRect)"))
        XCTAssertTrue(coordinator.contains("captureService.captureWindow("))
    }

    func testStillImageToolbarOffersInlineTextAnnotation() throws {
        let source = try selectionOverlaySource()

        XCTAssertTrue(source.contains("addTextToolButton()"))
        XCTAssertTrue(source.contains("help: \"文字\""))
        XCTAssertTrue(source.contains("beginTextEditing(at:"))
    }

    func testTextToolUsesPlainTIconWithoutFormatLabel() throws {
        let source = try selectionOverlaySource()

        XCTAssertTrue(source.contains("makeTextToolImage"))
        XCTAssertTrue(source.contains("NSString(string: \"T\")"))
        XCTAssertFalse(source.contains("symbol: \"textformat\""))
        XCTAssertFalse(source.contains("\"格式\""))
        XCTAssertTrue(source.contains("candidate == .text ? .systemGreen : .systemCyan"))
    }

    func testTextToolMatchesWechatStyleControlsAndSelection() throws {
        let source = try selectionOverlaySource()

        XCTAssertFalse(source.contains("NSColorWell"))
        XCTAssertTrue(source.contains("textOptionsBar"))
        XCTAssertTrue(source.contains("textSizePopUp"))
        XCTAssertTrue(source.contains("textColorSwatchTapped"))
        XCTAssertTrue(source.contains("TextAnnotationHandle.allCases"))
        XCTAssertTrue(source.contains("activeTextMove"))
        XCTAssertTrue(source.contains("TextAnnotationLayout.resize"))
        XCTAssertTrue(source.contains("TextAnnotationLayout.move"))
        XCTAssertTrue(source.contains("placeholder.alignment = .center"))
        XCTAssertTrue(source.contains("textView.textContainer?.lineBreakMode = .byWordWrapping"))
        XCTAssertTrue(source.contains("textView.textContainer?.lineFragmentPadding = 0"))
        XCTAssertTrue(source.contains("TextAnnotationLayout.horizontalTextInset"))
        XCTAssertTrue(source.contains("TextAnnotationLayout.verticalTextInset"))
        XCTAssertTrue(source.contains("TextAnnotationLayout.effectiveContentWidth(for: contentRect.width)"))
    }

    func testTextInputUsesWechatStyleMultilineEditorWithLiveDragHandles() throws {
        let source = try selectionOverlaySource()

        XCTAssertTrue(source.contains("final class TextAnnotationEditorView"))
        XCTAssertTrue(source.contains("private let textView = NSTextView"))
        XCTAssertTrue(source.contains("textContainer?.widthTracksTextView = true"))
        XCTAssertTrue(source.contains("textView.drawsBackground = false"))
        XCTAssertTrue(source.contains("drawEditorChrome()"))
        XCTAssertTrue(source.contains("onResize"))
        XCTAssertTrue(source.contains("onMove"))
        XCTAssertTrue(source.contains("resizeActiveTextEditor"))
        XCTAssertTrue(source.contains("moveActiveTextEditor"))
        XCTAssertTrue(source.contains("if hit === placeholder { return textView }"))
        XCTAssertTrue(source.contains("deleteSelectedTextAnnotation"))
        XCTAssertFalse(source.contains("field.backgroundColor = NSColor.black.withAlphaComponent"))
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

    private func selectionOverlaySource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PinSnip/Capture/SelectionOverlayView.swift"
            ),
            encoding: .utf8
        )
    }
}
