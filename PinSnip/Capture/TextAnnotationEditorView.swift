import AppKit
import PinSnipCore

@MainActor
final class TextAnnotationEditorView: NSView, NSTextViewDelegate {
    private enum DragMode {
        case resize(TextAnnotationHandle, startPoint: CGPoint, rect: CGRect)
        case move(startPoint: CGPoint)
    }

    private static let chromeInset = TextAnnotationLayout.chromeInset
    private let textView = NSTextView()
    private let placeholder = NSTextField(labelWithString: "输入文字")
    private var dragMode: DragMode?
    private var dragHasStarted = false
    private var cursorTrackingArea: NSTrackingArea?

    var onTextChange: ((String) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTransformBegan: (() -> Void)?
    var onResize: ((TextAnnotationHandle, CGPoint) -> Void)?
    var onMove: ((CGSize) -> Void)?
    var onTransformEnded: (() -> Void)?

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            updatePlaceholder()
        }
    }

    init(frame frameRect: NSRect, font: NSFont, color: NSColor) {
        super.init(frame: frameRect)
        wantsLayer = true

        textView.font = font
        textView.textColor = color
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainerInset = NSSize(
            width: TextAnnotationLayout.horizontalTextInset,
            height: TextAnnotationLayout.verticalTextInset
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = self
        addSubview(textView)

        placeholder.font = font
        placeholder.textColor = color
        placeholder.alignment = .left
        placeholder.isBezeled = false
        placeholder.drawsBackground = false
        placeholder.isSelectable = false
        addSubview(placeholder)
        toolTip = "拖动边框移动文字；左右控制点调整宽度；文字区域可编辑"
        setAccessibilityLabel("文字标注编辑框")
        updatePlaceholder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(annotationRect: CGRect) {
        frame = annotationRect.insetBy(
            dx: -Self.chromeInset,
            dy: -Self.chromeInset
        )
        needsLayout = true
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func update(font: NSFont, color: NSColor) {
        textView.font = font
        textView.textColor = color
        placeholder.font = font
        placeholder.textColor = color
        needsLayout = true
    }

    func focus(selectAll: Bool) {
        window?.makeFirstResponder(textView)
        if selectAll {
            textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        }
    }

    override func layout() {
        super.layout()
        let contentRect = bounds.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
        textView.frame = contentRect
        placeholder.frame = TextAnnotationLayout.contentRect(in: contentRect)
        textView.textContainer?.containerSize = NSSize(
            width: TextAnnotationLayout.effectiveContentWidth(for: contentRect.width),
            height: .greatestFiniteMagnitude
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawEditorChrome()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
        addCursorRect(contentRect.insetBy(dx: 2, dy: 2), cursor: .iBeam)
        for handle in TextAnnotationHandle.allCases {
            addCursorRect(TextAnnotationLayout.handleRect(handle, in: contentRect, hitArea: true),
                          cursor: .resizeLeftRight)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if dragHasStarted {
            if case .move = dragMode { NSCursor.closedHand.set() }
            else { NSCursor.resizeLeftRight.set() }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        switch TextAnnotationLayout.hitTarget(at: point, in: contentRect) {
        case .resize: NSCursor.resizeLeftRight.set()
        case .move: NSCursor.openHand.set()
        default: NSCursor.iBeam.set()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // NSView.hitTest receives a point in the superview's coordinate system.
        let localPoint = convert(point, from: superview)
        guard !isHidden, bounds.contains(localPoint),
              let target = TextAnnotationLayout.hitTarget(at: localPoint, in: contentRect)
        else { return nil }
        switch target {
        case .resize, .move: return self
        case .text:
            let hit = super.hitTest(point)
            if hit === placeholder { return textView }
            return hit
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let point = superview?.convert(event.locationInWindow, from: nil) ?? localPoint
        dragHasStarted = false
        switch TextAnnotationLayout.hitTarget(at: localPoint, in: contentRect) {
        case let .resize(handle):
            dragMode = .resize(handle, startPoint: point, rect: convert(contentRect, to: superview))
        case .move:
            dragMode = .move(startPoint: point)
        default:
            dragMode = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }
        let point = superview?.convert(event.locationInWindow, from: nil)
            ?? convert(event.locationInWindow, from: nil)
        let start: CGPoint
        switch dragMode {
        case let .resize(_, startPoint, _), let .move(startPoint): start = startPoint
        }
        guard dragHasStarted || TextAnnotationLayout.hasDragged(from: start, to: point) else { return }
        if !dragHasStarted {
            onTransformBegan?()
            dragHasStarted = true
        }
        switch dragMode {
        case let .resize(handle, startPoint, rect):
            NSCursor.resizeLeftRight.set()
            onResize?(handle, TextAnnotationLayout.resizePoint(for: handle, in: rect, from: startPoint, to: point))
        case let .move(startPoint):
            NSCursor.closedHand.set()
            onMove?(CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragHasStarted { onTransformEnded?() }
        dragMode = nil
        dragHasStarted = false
        needsDisplay = true
        window?.makeFirstResponder(textView)
        window?.invalidateCursorRects(for: self)
        cursorUpdate(with: event)
    }

    func textDidChange(_ notification: Notification) {
        updatePlaceholder()
        onTextChange?(textView.string)
    }

    func textView(
        _ textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            onCommit?()
            return true
        }
        return false
    }

    private var contentRect: CGRect {
        bounds.insetBy(dx: Self.chromeInset, dy: Self.chromeInset)
    }

    private func drawEditorChrome() {
        TextAnnotationChrome.draw(in: contentRect, editing: true, dragging: dragHasStarted)
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !textView.string.isEmpty
    }
}

// Shared editing/selection chrome: text stays primary (§2.1); shape and cursor
// communicate the controls' roles as well as color (§5.7).
@MainActor
enum TextAnnotationChrome {
    static func draw(in rect: CGRect, editing: Bool, dragging: Bool = false) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        if !editing && !dragging { outline.setLineDash([2, 3], count: 2, phase: 0) }
        outline.lineWidth = 2
        NSColor.black.withAlphaComponent(0.65).setStroke()
        outline.stroke()
        outline.lineWidth = 1
        NSColor.white.setStroke()
        outline.stroke()
        for handle in TextAnnotationHandle.allCases {
            let path = NSBezierPath(ovalIn: TextAnnotationLayout.handleRect(handle, in: rect))
            (dragging ? NSColor.controlAccentColor : NSColor.white).setFill()
            NSColor.black.setStroke()
            path.lineWidth = 2
            path.fill()
            path.stroke()
        }
    }
}
