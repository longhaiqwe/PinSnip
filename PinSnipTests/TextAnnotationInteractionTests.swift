import AppKit
import XCTest
@testable import PinSnipCore

final class TextAnnotationInteractionTests: XCTestCase {
    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    func testArrowStylePickerAppearsOnlyForArrowTool() throws {
        let (window, unusedEditor, _) = makeEditor()
        unusedEditor.removeFromSuperview()
        defer { window.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
            bytesPerRow: 2400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var result: CaptureResult?
        let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
            initialSelectionRect: CGRect(x: 40, y: 90, width: 520, height: 260), purpose: .stillImage,
            onResult: { result = $0 }, onCancel: {})
        window.contentView = overlay
        let buttons = descendants(of: overlay).compactMap { $0 as? NSButton }
        let arrow = try XCTUnwrap(buttons.first { $0.toolTip == "箭头" })
        let hollow = try XCTUnwrap(buttons.first { $0.toolTip == "空心箭头" })
        XCTAssertTrue(hollow.isHiddenOrHasHiddenAncestor)
        arrow.performClick(nil)
        overlay.layoutSubtreeIfNeeded()
        XCTAssertFalse(hollow.isHiddenOrHasHiddenAncestor)
        hollow.performClick(nil)
        XCTAssertEqual(hollow.state, .on)
        let rectangle = try XCTUnwrap(buttons.first { $0.toolTip == "矩形" })
        rectangle.performClick(nil)
        XCTAssertTrue(hollow.isHiddenOrHasHiddenAncestor)
        arrow.performClick(nil)
        XCTAssertEqual(hollow.state, .on)
        overlay.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 150, y: 200), in: window))
        overlay.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 330, y: 240), in: window))
        overlay.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 330, y: 240), in: window))
        let undo = try XCTUnwrap(buttons.first { $0.toolTip == "撤销（⌘Z）" })
        let redo = try XCTUnwrap(buttons.first { $0.toolTip == "重做（⇧⌘Z）" })
        undo.performClick(nil)
        XCTAssertFalse(undo.isEnabled)
        redo.performClick(nil)
        let copy = try XCTUnwrap(buttons.first { $0.toolTip == "完成并复制分享图" })
        copy.performClick(nil)
        XCTAssertEqual(result?.annotations, [
            .arrow(from: CGPoint(x: 110, y: 110), to: CGPoint(x: 290, y: 150),
                   TextAnnotationPalette.colors.last!, 3, style: .hollow)
        ])
    }

    @MainActor
    func testClickTypingAndExportKeepSameTextAnchor() throws {
        let (window, unusedEditor, _) = makeEditor()
        unusedEditor.removeFromSuperview()
        defer { window.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
            bytesPerRow: 2400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var result: CaptureResult?
        let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
            initialSelectionRect: CGRect(x: 40, y: 90, width: 520, height: 260), purpose: .stillImage,
            onResult: { result = $0 }, onCancel: {})
        window.contentView = overlay
        let textButton = try XCTUnwrap(descendants(of: overlay).compactMap { $0 as? NSButton }.first { $0.toolTip == "文字" })
        let buttons = descendants(of: overlay).compactMap { $0 as? NSButton }
        let undo = try XCTUnwrap(buttons.first { $0.tag == 10 })
        let redo = try XCTUnwrap(buttons.first { $0.tag == 11 })
        XCTAssertFalse(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        textButton.performClick(nil)
        let click = CGPoint(x: 180, y: 210)
        overlay.mouseDown(with: event(.leftMouseDown, at: click, in: window))
        let editor = try XCTUnwrap(overlay.subviews.compactMap { $0 as? TextAnnotationEditorView }.first)
        editor.layoutSubtreeIfNeeded()
        let initial = editor.frame.insetBy(dx: TextAnnotationLayout.chromeInset, dy: TextAnnotationLayout.chromeInset)
        XCTAssertEqual(initial.midY, click.y)
        XCTAssertEqual(initial.minX + TextAnnotationLayout.horizontalTextInset, click.x)
        let textView = try XCTUnwrap(editor.hitTest(click) as? NSTextView)
        textView.insertText("文字测试", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(undo.isEnabled, "Pending typed text can be committed and undone")
        XCTAssertFalse(redo.isEnabled)
        editor.layoutSubtreeIfNeeded()
        let typed = editor.frame.insetBy(dx: TextAnnotationLayout.chromeInset, dy: TextAnnotationLayout.chromeInset)
        XCTAssertEqual(typed.width, initial.width, "Typing the first character must not shrink the box")
        XCTAssertEqual(typed.maxY, initial.maxY)
        editor.onCommit?()
        undo.performClick(nil)
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(redo.isEnabled)
        redo.performClick(nil)
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        let center = CGPoint(x: typed.midX, y: typed.midY)
        overlay.mouseDown(with: event(.leftMouseDown, at: center, in: window))
        overlay.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: center.x + 35, y: center.y + 20), in: window))
        overlay.mouseDragged(with: event(.leftMouseDragged, at: center, in: window))
        overlay.mouseUp(with: event(.leftMouseUp, at: center, in: window))
        // A second drag moves the whole committed annotation and preserves its content.
        overlay.mouseDown(with: event(.leftMouseDown, at: center, in: window))
        let destination = CGPoint(x: center.x + 30, y: center.y + 20)
        overlay.mouseDragged(with: event(.leftMouseDragged, at: destination, in: window))
        overlay.mouseUp(with: event(.leftMouseUp, at: destination, in: window))
        let finish = try XCTUnwrap(descendants(of: overlay).compactMap { $0 as? NSButton }.first { $0.toolTip == "完成并复制分享图" })
        finish.performClick(nil)
        let annotation = try XCTUnwrap(result?.annotations.first)
        guard case let .text(rect, text, _, _) = annotation else { return XCTFail("Expected text output") }
        XCTAssertEqual(text, "文字测试")
        XCTAssertEqual(rect, typed.offsetBy(dx: 30 - 40, dy: 20 - 90),
                       "Export must preserve the anchor relative to the cropped selection")
    }

    @MainActor
    func testToolbarControlsRemainVisibleAtScreenEdgesAndNarrowWidths() throws {
        _ = NSApplication.shared
        for width: CGFloat in [375, 600, 1280] {
            for bottom: CGFloat in [0, 120, 380] {
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 560),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let context = try XCTUnwrap(CGContext(data: nil, width: Int(width), height: 560,
                    bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: width, height: 560),
                    screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
                    initialSelectionRect: CGRect(x: 20, y: bottom, width: width - 40, height: 160),
                    purpose: .stillImage, onResult: { _ in }, onCancel: {})
                window.contentView = overlay
                let buttons = descendants(of: overlay).compactMap { $0 as? NSButton }
                let textButton = try XCTUnwrap(buttons.first { $0.toolTip == "文字" })
                textButton.performClick(nil)
                overlay.layoutSubtreeIfNeeded()
                for button in buttons where !button.isHiddenOrHasHiddenAncestor {
                    let rect = overlay.convert(button.bounds, from: button)
                    XCTAssertTrue(overlay.bounds.insetBy(dx: 9, dy: 9).contains(rect),
                                  "\(button.toolTip ?? button.title) is clipped at width \(width), y \(bottom): \(rect)")
                }
                let panels = overlay.subviews.filter { !$0.isHidden && $0.subviews.contains { $0 is NSStackView } }
                XCTAssertEqual(panels.count, 2)
                XCTAssertFalse(panels[0].frame.intersects(panels[1].frame))
                XCTAssertEqual(textButton.state, .on)
                XCTAssertEqual(textButton.layer?.borderWidth, 1)
                let white = try XCTUnwrap(buttons.first { $0.toolTip == "文字颜色：白色" })
                white.performClick(nil)
                XCTAssertEqual(white.state, .on)
                XCTAssertNotNil(white.image)
                XCTAssertEqual(buttons.filter { $0.toolTip?.hasPrefix("文字颜色：") == true && $0.image != nil }.count, 1)
            }
        }
    }

    @MainActor
    func testRecordingAndScrollingPrimaryActionsKeepExpectedBehavior() throws {
        for purpose in [CaptureOverlayPurpose.animatedGIF, .scrollingCapture] {
            let (window, _, _) = makeEditor()
            defer { window.close() }
            let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
                bytesPerRow: 2400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            var result: CaptureResult?
            let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
                initialSelectionRect: CGRect(x: 30, y: 80, width: 540, height: 280), purpose: purpose,
                onResult: { result = $0 }, onCancel: {})
            window.contentView = overlay
            overlay.layoutSubtreeIfNeeded()
            let primary = try XCTUnwrap(descendants(of: overlay).compactMap { $0 as? NSButton }
                .first { $0.title == (purpose == .animatedGIF ? "录制" : "开始") })
            XCTAssertTrue(overlay.bounds.contains(overlay.convert(primary.bounds, from: primary)))
            primary.performClick(nil)
            if purpose == .animatedGIF {
                guard case .recordGIF = result?.action else { return XCTFail("Expected GIF recording") }
            } else {
                guard case .scrollCapture = result?.action else { return XCTFail("Expected scrolling capture") }
            }
        }
    }

    @MainActor
    func testNumberSizesEditExistingBadgesAndPreserveSequenceAndUndo() throws {
        let (window, _, _) = makeEditor()
        defer { window.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
            bytesPerRow: 2400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var result: CaptureResult?
        let selection = CGRect(x: 40, y: 90, width: 520, height: 260)
        let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            screenshot: try XCTUnwrap(context.makeImage()), windowCandidates: [], initialPointer: .zero,
            initialSelectionRect: selection, purpose: .stillImage,
            onResult: { result = $0 }, onCancel: {})
        window.contentView = overlay
        let buttons = descendants(of: overlay).compactMap { $0 as? NSButton }
        try XCTUnwrap(buttons.first { $0.toolTip == "序号" }).performClick(nil)
        overlay.layoutSubtreeIfNeeded()
        let size = try XCTUnwrap(buttons.compactMap { $0 as? NSPopUpButton }.first { $0.toolTip == "序号大小" })
        XCTAssertFalse(size.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(size.titleOfSelectedItem, "中")
        func click(_ point: CGPoint) {
            overlay.mouseDown(with: event(.leftMouseDown, at: point, in: window))
            overlay.mouseUp(with: event(.leftMouseUp, at: point, in: window))
        }
        func choose(_ preset: NumberAnnotationSizePreset) {
            size.selectItem(at: preset.rawValue)
            size.sendAction(size.action, to: size.target)
        }
        click(CGPoint(x: 42, y: 170))
        choose(.extraLarge) // Enlarging near the edge must keep the badge inside the crop.
        click(CGPoint(x: 220, y: 200)) // New number inherits the chosen size.
        click(CGPoint(x: 68, y: 170)) // Select number 1 instead of appending number 3.
        choose(.small)
        try XCTUnwrap(buttons.first { $0.tag == 10 }).performClick(nil)
        try XCTUnwrap(buttons.first { $0.tag == 11 }).performClick(nil)
        try XCTUnwrap(buttons.first { $0.toolTip == "完成并复制分享图" }).performClick(nil)
        let annotations = try XCTUnwrap(result?.annotations)
        XCTAssertEqual(annotations.count, 2)
        for (index, annotation) in annotations.enumerated() {
            guard case let .number(center, value, _, diameter) = annotation else { return XCTFail("Expected number") }
            XCTAssertEqual(value, index + 1)
            XCTAssertEqual(diameter, index == 0 ? 20 : 56)
            let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                              width: diameter, height: diameter)
            XCTAssertTrue(CGRect(origin: .zero, size: selection.size).contains(rect))
        }
    }

    @MainActor
    private func makeEditor() -> (NSWindow, TextAnnotationEditorView, CGRect) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 600, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let rect = CGRect(x: 180, y: 150, width: 160, height: 32)
        let editor = TextAnnotationEditorView(frame: .zero, font: .systemFont(ofSize: 22), color: .black)
        window.contentView!.addSubview(editor)
        editor.update(annotationRect: rect)
        editor.layoutSubtreeIfNeeded()
        return (window, editor, rect)
    }

    @MainActor
    private func event(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                          clickCount: 1, pressure: 1)!
    }

    @MainActor
    func testHitTestingUsesSuperviewCoordinatesAwayFromOrigin() {
        let (window, editor, rect) = makeEditor()
        defer { window.close() }
        XCTAssertTrue(editor.hitTest(CGPoint(x: rect.midX, y: rect.midY)) is NSTextView)
        XCTAssertTrue(editor.hitTest(CGPoint(x: rect.midX, y: rect.maxY + 5)) === editor)
        XCTAssertTrue(editor.hitTest(CGPoint(x: rect.maxX + 8, y: rect.midY)) === editor)
        XCTAssertNil(editor.hitTest(CGPoint(x: 20, y: 16)))
        editor.update(annotationRect: rect.offsetBy(dx: 100, dy: 50))
        editor.layoutSubtreeIfNeeded()
        XCTAssertTrue(editor.hitTest(CGPoint(x: rect.midX + 100, y: rect.midY + 50)) is NSTextView)
        XCTAssertNil(editor.hitTest(CGPoint(x: rect.minX, y: rect.midY)))
    }

    @MainActor
    func testResizeDoesNotJumpWhenGrabbingOuterHitArea() {
        let (window, editor, rect) = makeEditor()
        defer { window.close() }
        let start = CGPoint(x: rect.maxX + 8, y: rect.midY)
        var positions: [CGPoint] = []
        var began = 0
        var ended = 0
        editor.onResize = { _, point in positions.append(point) }
        editor.onTransformBegan = { began += 1 }
        editor.onTransformEnded = { ended += 1 }
        editor.mouseDown(with: event(.leftMouseDown, at: start, in: window))
        editor.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: start.x + 1, y: start.y), in: window))
        XCTAssertTrue(positions.isEmpty)
        editor.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: start.x + 20, y: start.y), in: window))
        editor.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: start.x + 20, y: start.y), in: window))
        XCTAssertEqual(positions.first?.x, rect.maxX + 20)
        XCTAssertEqual(began, 1)
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testBorderDragKeepsOriginalAnchorAfterEditorMoves() {
        let (window, editor, rect) = makeEditor()
        defer { window.close() }
        let start = CGPoint(x: rect.midX, y: rect.maxY + 5)
        var offsets: [CGSize] = []
        editor.onMove = { offset in
            offsets.append(offset)
            editor.update(annotationRect: rect.offsetBy(dx: offset.width, dy: offset.height))
            editor.layoutSubtreeIfNeeded()
        }
        editor.mouseDown(with: event(.leftMouseDown, at: start, in: window))
        editor.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: start.x + 20, y: start.y + 10), in: window))
        editor.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: start.x + 30, y: start.y + 15), in: window))
        editor.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: start.x + 30, y: start.y + 15), in: window))
        XCTAssertEqual(offsets, [CGSize(width: 20, height: 10), CGSize(width: 30, height: 15)])
    }

    @MainActor
    func testBorderClickDoesNotCreateTransformAndPreservesTextSelection() throws {
        let (window, editor, rect) = makeEditor()
        defer { window.close() }
        editor.text = "保留选中文字"
        let textView = try XCTUnwrap(editor.hitTest(CGPoint(x: rect.midX, y: rect.midY)) as? NSTextView)
        textView.setSelectedRange(NSRange(location: 1, length: 2))
        var began = false
        editor.onTransformBegan = { began = true }
        let point = CGPoint(x: rect.midX, y: rect.maxY + 5)
        editor.mouseDown(with: event(.leftMouseDown, at: point, in: window))
        editor.mouseUp(with: event(.leftMouseUp, at: point, in: window))
        XCTAssertFalse(began)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 2))
    }
}
