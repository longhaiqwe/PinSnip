import AppKit
import PinSnipCore

enum CaptureOverlayPurpose: Equatable {
    case stillImage
    case animatedGIF
    case scrollingCapture
}

enum CaptureResultAction {
    case copy
    case save
    case pin
    case recordGIF
    case scrollCapture
}

struct CaptureResult {
    let image: CGImage
    let annotations: [Annotation]
    let selectionRect: CGRect
    let windowID: CGWindowID?
    let action: CaptureResultAction
}

@MainActor
final class TextAnnotationEditorView: NSView, NSTextViewDelegate {
    private enum DragMode {
        case resize(TextAnnotationHandle)
        case move(startPoint: CGPoint)
    }

    private static let chromeInset: CGFloat = 9
    private let textView = NSTextView()
    private let placeholder = NSTextField(labelWithString: "输入文字")
    private var dragMode: DragMode?

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
        placeholder.textColor = NSColor.secondaryLabelColor
        placeholder.alignment = .center
        placeholder.isBezeled = false
        placeholder.drawsBackground = false
        placeholder.isSelectable = false
        addSubview(placeholder)
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
        placeholder.frame = contentRect.insetBy(dx: 6, dy: 2)
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
        for handle in TextAnnotationHandle.allCases {
            addCursorRect(handleRect(for: handle).insetBy(dx: -3, dy: -3), cursor: .resizeLeftRight)
        }
        for rect in borderDragRects {
            addCursorRect(rect, cursor: .openHand)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if handle(at: point) != nil || borderDragRects.contains(where: { $0.contains(point) }) {
            return self
        }
        let hit = super.hitTest(point)
        if hit === placeholder { return textView }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let point = superview?.convert(event.locationInWindow, from: nil) ?? localPoint
        onTransformBegan?()
        if let handle = handle(at: localPoint) {
            dragMode = .resize(handle)
        } else {
            dragMode = .move(startPoint: point)
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }
        let point = superview?.convert(event.locationInWindow, from: nil)
            ?? convert(event.locationInWindow, from: nil)
        switch dragMode {
        case let .resize(handle):
            onResize?(handle, point)
        case let .move(startPoint):
            onMove?(CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
        onTransformEnded?()
        window?.makeFirstResponder(textView)
        window?.invalidateCursorRects(for: self)
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

    private var borderDragRects: [CGRect] {
        let rect = contentRect
        return [
            CGRect(x: rect.minX - 6, y: rect.minY - 6, width: rect.width + 12, height: 6),
            CGRect(x: rect.minX - 6, y: rect.maxY, width: rect.width + 12, height: 6),
            CGRect(x: rect.minX - 6, y: rect.minY, width: 6, height: rect.height),
            CGRect(x: rect.maxX, y: rect.minY, width: 6, height: rect.height)
        ]
    }

    private func handleRect(for handle: TextAnnotationHandle) -> CGRect {
        let rect = contentRect
        let center = CGPoint(
            x: handle.horizontalEdge == .left ? rect.minX : rect.maxX,
            y: handle == .topLeft || handle == .topRight ? rect.maxY : rect.minY
        )
        return CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
    }

    private func handle(at point: CGPoint) -> TextAnnotationHandle? {
        TextAnnotationHandle.allCases.first {
            handleRect(for: $0).insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func drawEditorChrome() {
        let outline = NSBezierPath(rect: contentRect.insetBy(dx: -2, dy: -2))
        outline.lineWidth = 1
        outline.setLineDash([2, 3], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.82).setStroke()
        outline.stroke()
        for handle in TextAnnotationHandle.allCases {
            NSColor.white.setFill()
            NSColor.systemGray.setStroke()
            let path = NSBezierPath(ovalIn: handleRect(for: handle))
            path.lineWidth = 2
            path.fill()
            path.stroke()
        }
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !textView.string.isEmpty
    }
}

@MainActor
final class SelectionOverlayView: NSView {
    private enum Phase { case selecting, editing }
    private enum Tool: Int { case rectangle = 1, arrow = 2, pencil = 3, text = 4, number = 5, mosaic = 6, mosaicPencil = 7 }
    private enum AspectRatioOption: Int, CaseIterable {
        case free
        case square
        case fourThree
        case sixteenNine

        var title: String {
            switch self {
            case .free: "自由"
            case .square: "1:1"
            case .fourThree: "4:3"
            case .sixteenNine: "16:9"
            }
        }

        var constraint: SelectionConstraint? {
            switch self {
            case .free: nil
            case .square: SelectionConstraint(aspectRatio: 1)
            case .fourThree: SelectionConstraint(aspectRatio: 4.0 / 3.0)
            case .sixteenNine: SelectionConstraint(aspectRatio: 16.0 / 9.0)
            }
        }
    }

    private let screenshot: CGImage
    private let purpose: CaptureOverlayPurpose
    private let onResult: (CaptureResult) -> Void
    private let onCancel: () -> Void
    private var phase = Phase.selecting
    private var selectionState: WindowSelectionState
    private var editingSelectionRect: CGRect?
    private var activeResize: (handle: SelectionResizeHandle, initialRect: CGRect)?
    private var selectionRect: CGRect { editingSelectionRect ?? selectionState.rect }
    private var tool = Tool.rectangle
    private var annotationStart: CGPoint?
    private var currentAnnotation: Annotation?
    private var pencilPoints: [CGPoint] = []
    private var activeTextEditor: TextAnnotationEditorView?
    private var activeTextRect: CGRect?
    private var activeTextEditingIndex: Int?
    private var activeTextTransformOrigin: CGRect?
    private var activeTextWidthWasAdjusted = false
    private var selectedTextIndex: Int?
    private var activeTextResize: (
        index: Int,
        handle: TextAnnotationHandle,
        original: Annotation
    )?
    private var activeTextMove: (
        index: Int,
        startPoint: CGPoint,
        original: Annotation
    )?
    private var textTransformPreview: Annotation?
    private var document = AnnotationDocument()
    private var cachedMosaicNSImage: NSImage?
    private var mosaicNSImage: NSImage? {
        if let cachedMosaicNSImage { return cachedMosaicNSImage }
        let scale = CGFloat(screenshot.width) / max(1, bounds.width)
        let pixelSize = max(4, 16 * scale)
        guard let cg = AnnotationRenderer.createMosaicImage(from: screenshot, pixelSize: pixelSize) else { return nil }
        let image = NSImage(cgImage: cg, size: bounds.size)
        cachedMosaicNSImage = image
        return image
    }
    private let toolbar = NSView()
    private let stack = NSStackView()
    private let selectionOptionsBar = NSView()
    private let selectionOptionsStack = NSStackView()
    private let aspectRatioPopUp = NSPopUpButton()
    private var aspectRatioOption = AspectRatioOption.free
    private var toolButtons: [Tool: NSButton] = [:]
    private let textOptionsBar = NSView()
    private let textOptionsStack = NSStackView()
    private let textSizePopUp = NSPopUpButton()
    private var textColorSwatches: [NSButton] = []
    private var annotationColor = TextAnnotationPalette.colors.last!
    private var annotationTextSize = TextAnnotationSizePreset.medium
    private static let dividerlessHorizontalResizeImage =
        makeDividerlessHorizontalResizeImage()
    private static let leftRightResizeCursor =
        directionalResizeCursor(byDegrees: 0)
    private static let upDownResizeCursor =
        directionalResizeCursor(byDegrees: 90)
    private static let diagonalNorthWestSouthEastCursor =
        directionalResizeCursor(byDegrees: -45)
    private static let diagonalNorthEastSouthWestCursor =
        directionalResizeCursor(byDegrees: 45)

    init(
        frame frameRect: NSRect,
        screenshot: CGImage,
        windowCandidates: [WindowCandidate],
        initialPointer: CGPoint,
        initialSelectionRect: CGRect,
        purpose: CaptureOverlayPurpose,
        onResult: @escaping (CaptureResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenshot = screenshot
        self.purpose = purpose
        self.onResult = onResult
        self.onCancel = onCancel
        var selectionState = WindowSelectionState(
            candidates: windowCandidates,
            initialRect: initialSelectionRect
        )
        if initialSelectionRect.isEmpty {
            selectionState.hover(at: initialPointer)
        }
        self.selectionState = selectionState
        super.init(frame: frameRect)
        phase = initialSelectionRect.isEmpty ? .selecting : .editing
        editingSelectionRect = initialSelectionRect.isEmpty ? nil : initialSelectionRect
        wantsLayer = true
        configureToolbar()
        configureTextOptionsBar()
        configureSelectionOptionsBar()
        toolbar.isHidden = phase == .selecting
        textOptionsBar.isHidden = phase == .selecting || tool != .text
        selectionOptionsBar.isHidden = phase == .editing
        if phase == .editing { updateToolButtons() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard phase == .editing else { return }

        for handle in SelectionResizeHandle.allCases {
            let center = SelectionAdjustment.center(of: handle, in: selectionRect)
            let radius = SelectionOverlayStyle.handleHitRadius
            addCursorRect(
                CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ),
                cursor: Self.cursor(for: SelectionAdjustment.cursor(for: handle))
            )
        }
        if let rect = selectedTextRect {
            for handle in TextAnnotationHandle.allCases {
                addCursorRect(
                    textResizeHandleRect(handle: handle, in: rect).insetBy(dx: -3, dy: -3),
                    cursor: Self.leftRightResizeCursor
                )
            }
        }
    }

    private static func cursor(for resizeCursor: SelectionResizeCursor) -> NSCursor {
        switch resizeCursor {
        case .leftRight:
            leftRightResizeCursor
        case .upDown:
            upDownResizeCursor
        case .diagonalNorthWestSouthEast:
            diagonalNorthWestSouthEastCursor
        case .diagonalNorthEastSouthWest:
            diagonalNorthEastSouthWestCursor
        }
    }

    private static func directionalResizeCursor(byDegrees degrees: CGFloat) -> NSCursor {
        let sourceImage = dividerlessHorizontalResizeImage
        let sourceSize = sourceImage.size
        let radians = degrees * .pi / 180
        let absoluteCosine = abs(cos(radians))
        let absoluteSine = abs(sin(radians))
        let imageSize = NSSize(
            width: ceil(sourceSize.width * absoluteCosine + sourceSize.height * absoluteSine),
            height: ceil(sourceSize.width * absoluteSine + sourceSize.height * absoluteCosine)
        )
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: degrees)
            transform.translateX(
                by: -sourceSize.width / 2,
                yBy: -sourceSize.height / 2
            )
            transform.concat()
            sourceImage.draw(
                in: CGRect(origin: .zero, size: sourceSize),
                from: CGRect(origin: .zero, size: sourceSize),
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return NSCursor(
            image: image,
            hotSpot: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        )
    }

    private static func makeDividerlessHorizontalResizeImage() -> NSImage {
        let systemImage = NSCursor.resizeLeftRight.image
        return NSImage(size: systemImage.size, flipped: false) { rect in
            let dividerRect = SelectionResizeCursorArtwork.centerDividerClearRect(
                in: systemImage.size
            )
            let inset = SelectionResizeCursorArtwork.arrowInsetTowardsCenter
            let leftSourceRect = CGRect(
                x: 0,
                y: 0,
                width: dividerRect.minX,
                height: systemImage.size.height
            )
            let rightSourceRect = CGRect(
                x: dividerRect.maxX,
                y: 0,
                width: systemImage.size.width - dividerRect.maxX,
                height: systemImage.size.height
            )
            systemImage.draw(
                in: leftSourceRect.offsetBy(dx: inset, dy: 0),
                from: leftSourceRect,
                operation: .sourceOver,
                fraction: 1
            )
            systemImage.draw(
                in: rightSourceRect.offsetBy(dx: -inset, dy: 0),
                from: rightSourceRect,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
    }

    func addWindowCandidates(_ candidates: [WindowCandidate]) {
        guard phase == .selecting, !candidates.isEmpty else { return }
        let pointer = bounded(window?.mouseLocationOutsideOfEventStream ?? .zero)
        selectionState.addCandidates(candidates, hoveringAt: pointer)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        layoutSelectionOptionsBar()
        layoutToolbar()
        layoutTextOptionsBar()
    }

    override func draw(_ dirtyRect: NSRect) {
        let image = NSImage(cgImage: screenshot, size: bounds.size)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        if selectionRect.isEmpty {
            drawCrosshair(at: window?.mouseLocationOutsideOfEventStream ?? .zero)
            return
        }

        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(selectionRect)
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(
            CaptureOverlayPresentationPolicy.dimmingOpacity(hasSelection: true)
        ).setFill()
        mask.fill()

        let borderColor = SelectionOverlayStyle.selectionBorderColor
        NSColor(
            srgbRed: borderColor.red,
            green: borderColor.green,
            blue: borderColor.blue,
            alpha: borderColor.alpha
        ).setStroke()
        let borderInset = SelectionOverlayStyle.selectionBorderWidth / 2
        let border = NSBezierPath(
            rect: selectionRect.insetBy(dx: borderInset, dy: borderInset)
        )
        border.lineWidth = SelectionOverlayStyle.selectionBorderWidth
        border.stroke()

        for (index, annotation) in document.annotations.enumerated() {
            if index == activeTextEditingIndex {
                continue
            } else if index == selectedTextIndex, let textTransformPreview {
                draw(textTransformPreview)
            } else {
                draw(annotation)
            }
        }
        if let currentAnnotation {
            draw(currentAnnotation)
        }
        drawSelectedTextBox()
        drawSizeLabel()
        if phase == .editing {
            for handle in SelectionResizeHandle.allCases {
                let center = SelectionAdjustment.center(of: handle, in: selectionRect)
                let ringColor = SelectionOverlayStyle.handleRingColor
                NSColor(
                    srgbRed: ringColor.red,
                    green: ringColor.green,
                    blue: ringColor.blue,
                    alpha: ringColor.alpha
                ).setFill()
                NSBezierPath(
                    ovalIn: SelectionOverlayStyle.handleOuterRect(centeredAt: center)
                ).fill()

                let centerColor = SelectionOverlayStyle.handleCenterColor
                NSColor(
                    srgbRed: centerColor.red,
                    green: centerColor.green,
                    blue: centerColor.blue,
                    alpha: centerColor.alpha
                ).setFill()
                NSBezierPath(
                    ovalIn: SelectionOverlayStyle.handleInnerRect(centeredAt: center)
                ).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch phase {
        case .selecting:
            selectionState.begin(at: point)
            toolbar.isHidden = true
        case .editing:
            commitTextEditing()
            if let handle = textResizeHandle(at: point),
               let index = selectedTextIndex,
               document.annotations.indices.contains(index) {
                activeTextResize = (index, handle, document.annotations[index])
                activeTextMove = nil
                textTransformPreview = document.annotations[index]
                annotationStart = nil
                currentAnnotation = nil
                pencilPoints.removeAll()
                return
            }
            if let handle = SelectionAdjustment.handle(
                at: point,
                in: selectionRect,
                hitRadius: SelectionOverlayStyle.handleHitRadius
            ) {
                activeResize = (handle, selectionRect)
                annotationStart = nil
                currentAnnotation = nil
                pencilPoints.removeAll()
                return
            }
            guard purpose == .stillImage else { return }
            guard selectionRect.contains(point) else { return }
            if tool == .text {
                if let index = textAnnotationIndex(at: point) {
                    if event.clickCount >= 2 {
                        beginTextEditing(at: point, index: index)
                        return
                    }
                    selectText(at: index)
                    activeTextMove = (index, point, document.annotations[index])
                    textTransformPreview = document.annotations[index]
                    return
                }
                beginTextEditing(at: point)
                return
            }
            clearTextSelection()
            annotationStart = point
            pencilPoints = [point]
            currentAnnotation = annotation(from: point, to: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = bounded(convert(event.locationInWindow, from: nil))
        switch phase {
        case .selecting:
            selectionState.drag(
                to: point,
                inside: bounds,
                constraint: aspectRatioOption.constraint
            )
        case .editing:
            if let activeTextResize {
                textTransformPreview = resizedTextAnnotation(
                    activeTextResize.original,
                    handle: activeTextResize.handle,
                    to: point
                )
                needsDisplay = true
                return
            }
            if let activeTextMove {
                textTransformPreview = movedTextAnnotation(
                    activeTextMove.original,
                    by: CGSize(
                        width: point.x - activeTextMove.startPoint.x,
                        height: point.y - activeTextMove.startPoint.y
                    )
                )
                needsDisplay = true
                return
            }
            if let activeResize {
                editingSelectionRect = SelectionAdjustment.resize(
                    activeResize.initialRect,
                    using: activeResize.handle,
                    to: point,
                    inside: bounds,
                    minimumDimension: 3
                )
                needsLayout = true
                needsDisplay = true
                return
            }
            guard let start = annotationStart else { return }
            if tool == .pencil || tool == .mosaicPencil {
                pencilPoints.append(point)
            }
            currentAnnotation = annotation(from: start, to: point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch phase {
        case .selecting:
            guard selectionState.end(minimumDimension: 3) else {
                needsDisplay = true
                return
            }
            phase = .editing
            editingSelectionRect = selectionState.rect
            toolbar.isHidden = false
            textOptionsBar.isHidden = tool != .text
            selectionOptionsBar.isHidden = true
            updateToolButtons()
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        case .editing:
            if let activeTextResize {
                if let textTransformPreview {
                    _ = document.replace(at: activeTextResize.index, with: textTransformPreview)
                }
                selectedTextIndex = activeTextResize.index
                self.activeTextResize = nil
                textTransformPreview = nil
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            if let activeTextMove {
                if let textTransformPreview {
                    _ = document.replace(at: activeTextMove.index, with: textTransformPreview)
                }
                selectedTextIndex = activeTextMove.index
                self.activeTextMove = nil
                textTransformPreview = nil
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            if activeResize != nil {
                activeResize = nil
                needsLayout = true
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            if let currentAnnotation {
                document.append(currentAnnotation)
            }
            annotationStart = nil
            currentAnnotation = nil
            pencilPoints.removeAll()
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard phase == .selecting else { return }
        selectionState.hover(at: bounded(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    @discardableResult
    private func deleteSelectedTextAnnotation() -> Bool {
        guard let index = selectedTextIndex,
              document.annotations.indices.contains(index),
              case .text = document.annotations[index]
        else { return false }
        guard document.remove(at: index) else { return false }
        clearTextSelection()
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if deleteSelectedTextAnnotation() { return }
        }
        if event.keyCode == 53 {
            onCancel()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            event.modifierFlags.contains(.shift) ? document.redo() : document.undo()
            needsDisplay = true
            return
        }
        if event.keyCode == 36 {
            switch purpose {
            case .stillImage: finish(.copy)
            case .animatedGIF: finish(.recordGIF)
            case .scrollingCapture: finish(.scrollCapture)
            }
            return
        }
        super.keyDown(with: event)
    }

    private func configureToolbar() {
        toolbar.appearance = CaptureToolbarStyle.usesLightControls
            ? NSAppearance(named: .aqua)
            : nil
        toolbar.wantsLayer = true
        let background = CaptureToolbarStyle.backgroundColor
        toolbar.layer?.backgroundColor = NSColor(
            srgbRed: background.red,
            green: background.green,
            blue: background.blue,
            alpha: background.alpha
        ).cgColor
        toolbar.layer?.cornerRadius = 12
        toolbar.layer?.masksToBounds = true
        toolbar.isHidden = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)
        toolbar.addSubview(stack)
        addSubview(toolbar)

        if purpose == .animatedGIF {
            CaptureToolbarLayout.animatedGIFActions.forEach(addActionButton)
            return
        }
        if purpose == .scrollingCapture {
            CaptureToolbarLayout.scrollingCaptureActions.forEach(addActionButton)
            return
        }

        addToolButton(.rectangle, symbol: "rectangle", help: "矩形")
        addToolButton(.arrow, symbol: "arrow.up.right", help: "箭头")
        addToolButton(.pencil, symbol: "pencil.tip", help: "画笔")
        addTextToolButton()
        addToolButton(.number, symbol: "number.circle", help: "序号")
        addToolButton(.mosaic, symbol: "checkerboard.rectangle", help: "矩形马赛克")
        addToolButton(.mosaicPencil, symbol: "square.grid.3x3.square", help: "画笔马赛克")
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(button(symbol: "arrow.uturn.backward", help: "撤销", tag: 10))
        stack.addArrangedSubview(button(symbol: "arrow.uturn.forward", help: "重做", tag: 11))
        stack.addArrangedSubview(separator())
        CaptureToolbarLayout.stillImageTrailingActions.forEach(addActionButton)
    }

    private func configureSelectionOptionsBar() {
        selectionOptionsBar.appearance = CaptureToolbarStyle.usesLightControls
            ? NSAppearance(named: .aqua)
            : nil
        selectionOptionsBar.wantsLayer = true
        let background = CaptureToolbarStyle.backgroundColor
        selectionOptionsBar.layer?.backgroundColor = NSColor(
            srgbRed: background.red,
            green: background.green,
            blue: background.blue,
            alpha: background.alpha
        ).cgColor
        selectionOptionsBar.layer?.cornerRadius = 10
        selectionOptionsBar.layer?.masksToBounds = true

        selectionOptionsStack.orientation = .horizontal
        selectionOptionsStack.alignment = .centerY
        selectionOptionsStack.spacing = 8
        selectionOptionsStack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)

        let label = NSTextField(labelWithString: "选区比例")
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 12, weight: .medium)
        selectionOptionsStack.addArrangedSubview(label)

        aspectRatioPopUp.addItems(withTitles: AspectRatioOption.allCases.map(\.title))
        aspectRatioPopUp.selectItem(at: aspectRatioOption.rawValue)
        aspectRatioPopUp.target = self
        aspectRatioPopUp.action = #selector(aspectRatioChanged(_:))
        aspectRatioPopUp.toolTip = "拖动前选择固定长宽比"
        aspectRatioPopUp.widthAnchor.constraint(equalToConstant: 88).isActive = true
        selectionOptionsStack.addArrangedSubview(aspectRatioPopUp)

        selectionOptionsBar.addSubview(selectionOptionsStack)
        addSubview(selectionOptionsBar)
    }

    @objc private func aspectRatioChanged(_ sender: NSPopUpButton) {
        guard let option = AspectRatioOption(rawValue: sender.indexOfSelectedItem) else { return }
        aspectRatioOption = option
    }

    private func addToolButton(_ tool: Tool, symbol: String, help: String) {
        let control = button(symbol: symbol, help: help, tag: tool.rawValue)
        control.setButtonType(.toggle)
        toolButtons[tool] = control
        stack.addArrangedSubview(control)
    }

    private func addTextToolButton() {
        let control = button(image: Self.makeTextToolImage(), help: "文字", tag: Tool.text.rawValue)
        control.setButtonType(.toggle)
        toolButtons[.text] = control
        stack.addArrangedSubview(control)
    }

    private static func makeTextToolImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let text = NSString(string: "T")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: rect.midX - textSize.width / 2,
                    y: rect.midY - textSize.height / 2
                ),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private func configureTextOptionsBar() {
        textOptionsBar.appearance = NSAppearance(named: .aqua)
        textOptionsBar.wantsLayer = true
        textOptionsBar.layer?.backgroundColor = NSColor.white.cgColor
        textOptionsBar.layer?.cornerRadius = 10
        textOptionsBar.layer?.shadowColor = NSColor.black.cgColor
        textOptionsBar.layer?.shadowOpacity = 0.2
        textOptionsBar.layer?.shadowRadius = 8
        textOptionsBar.layer?.shadowOffset = CGSize(width: 0, height: -2)
        textOptionsBar.isHidden = true

        textOptionsStack.orientation = .horizontal
        textOptionsStack.alignment = .centerY
        textOptionsStack.spacing = 7
        textOptionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        textSizePopUp.addItems(withTitles: TextAnnotationSizePreset.allCases.map(\.title))
        textSizePopUp.selectItem(at: annotationTextSize.rawValue)
        textSizePopUp.target = self
        textSizePopUp.action = #selector(textSizeChanged(_:))
        textSizePopUp.toolTip = "文字大小"
        textSizePopUp.widthAnchor.constraint(equalToConstant: 58).isActive = true
        textOptionsStack.addArrangedSubview(textSizePopUp)

        for (index, color) in TextAnnotationPalette.colors.enumerated() {
            let swatch = NSButton(title: "", target: self, action: #selector(textColorSwatchTapped(_:)))
            swatch.isBordered = false
            swatch.tag = index
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = nsColor(color).cgColor
            swatch.layer?.cornerRadius = 4
            swatch.toolTip = "文字颜色"
            swatch.widthAnchor.constraint(equalToConstant: 30).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 30).isActive = true
            textColorSwatches.append(swatch)
            textOptionsStack.addArrangedSubview(swatch)
        }

        textOptionsBar.addSubview(textOptionsStack)
        addSubview(textOptionsBar)
        updateTextStyleControls()
    }

    @objc private func textColorSwatchTapped(_ sender: NSButton) {
        guard TextAnnotationPalette.colors.indices.contains(sender.tag) else { return }
        annotationColor = TextAnnotationPalette.colors[sender.tag]
        activeTextEditor?.update(
            font: .systemFont(ofSize: annotationTextSize.fontSize),
            color: nsColor(annotationColor)
        )
        applySelectedTextStyle()
        updateTextStyleControls()
    }

    @objc private func textSizeChanged(_ sender: NSPopUpButton) {
        guard let preset = TextAnnotationSizePreset(rawValue: sender.indexOfSelectedItem) else {
            return
        }
        annotationTextSize = preset
        activeTextEditor?.update(
            font: .systemFont(ofSize: preset.fontSize),
            color: nsColor(annotationColor)
        )
        updateActiveTextEditorLayout(for: activeTextEditor?.text ?? "")
        applySelectedTextStyle()
    }

    private func addActionButton(_ action: CaptureToolbarAction) {
        let control: NSButton
        switch action {
        case .copy:
            control = button(
                symbol: "checkmark",
                help: "完成并复制分享图",
                tag: action.rawValue
            )
            control.contentTintColor = .systemGreen
        case .save:
            control = button(
                symbol: "square.and.arrow.down",
                help: "保存分享图",
                tag: action.rawValue
            )
        case .pin:
            control = button(
                symbol: "pin",
                help: "贴原图到屏幕",
                tag: action.rawValue
            )
        case .recordGIF:
            control = button(
                symbol: "record.circle.fill",
                help: "开始录制 GIF",
                tag: action.rawValue
            )
            control.contentTintColor = .systemRed
        case .scrollCapture:
            control = button(
                symbol: "rectangle.stack",
                help: "滚动截屏",
                tag: action.rawValue
            )
            control.contentTintColor = .systemCyan
        case .cancel:
            control = button(
                symbol: "xmark",
                help: "取消",
                tag: action.rawValue
            )
            control.contentTintColor = .systemRed
        }
        stack.addArrangedSubview(control)
    }

    private func button(symbol: String, help: String, tag: Int) -> NSButton {
        button(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!,
            help: help,
            tag: tag
        )
    }

    private func button(image: NSImage, help: String, tag: Int) -> NSButton {
        let control = NSButton(image: image, target: self, action: #selector(toolbarAction(_:)))
        control.isBordered = false
        control.imagePosition = .imageOnly
        control.toolTip = help
        control.tag = tag
        control.widthAnchor.constraint(equalToConstant: 30).isActive = true
        control.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return control
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }

    @objc private func toolbarAction(_ sender: NSButton) {
        if let selectedTool = Tool(rawValue: sender.tag) {
            commitTextEditing()
            tool = selectedTool
            if selectedTool != .text { clearTextSelection() }
            textOptionsBar.isHidden = selectedTool != .text
            updateToolButtons()
            needsLayout = true
            return
        }
        switch sender.tag {
        case 10:
            commitTextEditing(); clearTextSelection(); document.undo(); needsDisplay = true
        case 11:
            commitTextEditing(); clearTextSelection(); document.redo(); needsDisplay = true
        default:
            guard let action = CaptureToolbarAction(rawValue: sender.tag) else { return }
            switch action {
            case .copy: finish(.copy)
            case .save: finish(.save)
            case .pin: finish(.pin)
            case .recordGIF: finish(.recordGIF)
            case .scrollCapture: finish(.scrollCapture)
            case .cancel: onCancel()
            }
        }
    }

    private func updateToolButtons() {
        for (candidate, button) in toolButtons {
            button.state = candidate == tool ? .on : .off
            let selectedColor: NSColor = candidate == .text ? .systemGreen : .systemCyan
            button.contentTintColor = candidate == tool ? selectedColor : .labelColor
        }
    }

    private func updateTextStyleControls() {
        textSizePopUp.selectItem(at: annotationTextSize.rawValue)
        for (index, swatch) in textColorSwatches.enumerated() {
            let selected = TextAnnotationPalette.colors[index] == annotationColor
            swatch.layer?.borderWidth = selected ? 3 : 1
            swatch.layer?.borderColor = selected
                ? NSColor.systemGreen.cgColor
                : NSColor.separatorColor.cgColor
        }
    }

    private func applySelectedTextStyle() {
        guard let index = selectedTextIndex,
              document.annotations.indices.contains(index),
              case let .text(rect, text, _, _) = document.annotations[index]
        else { return }
        let top = rect.maxY
        var updatedRect = rect
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: rect.width,
            fontSize: annotationTextSize.fontSize
        )
        updatedRect.origin.y = max(selectionRect.minY, top - height)
        updatedRect.size.height = min(height, top - updatedRect.minY)
        _ = document.replace(
            at: index,
            with: .text(
                rect: updatedRect,
                text: text,
                color: annotationColor,
                fontSize: annotationTextSize.fontSize
            )
        )
        needsDisplay = true
    }

    private func layoutToolbar() {
        guard !toolbar.isHidden else { return }
        let desired = stack.fittingSize
        let width = desired.width
        let height = max(42, desired.height)
        var x = min(selectionRect.maxX - width, bounds.maxX - width - 10)
        x = max(10, x)
        var y = selectionRect.minY - height - 10
        if y < 10 { y = min(bounds.maxY - height - 10, selectionRect.maxY + 10) }
        toolbar.frame = NSRect(x: x, y: y, width: width, height: height)
        stack.frame = toolbar.bounds
    }

    private func layoutTextOptionsBar() {
        guard !textOptionsBar.isHidden else { return }
        let desired = textOptionsStack.fittingSize
        let width = desired.width
        let height = max(46, desired.height)
        let textButtonCenterX: CGFloat
        if let textButton = toolButtons[.text] {
            textButtonCenterX = convert(textButton.bounds, from: textButton).midX
        } else {
            textButtonCenterX = toolbar.frame.midX
        }
        var x = textButtonCenterX - width / 2
        x = min(max(10, x), bounds.maxX - width - 10)
        var y = toolbar.frame.minY - height - 10
        if y < 10 { y = min(bounds.maxY - height - 10, toolbar.frame.maxY + 10) }
        textOptionsBar.frame = CGRect(x: x, y: y, width: width, height: height)
        textOptionsStack.frame = textOptionsBar.bounds
    }

    private func layoutSelectionOptionsBar() {
        guard !selectionOptionsBar.isHidden else { return }
        let desired = selectionOptionsStack.fittingSize
        let width = desired.width
        let height = max(38, desired.height)
        selectionOptionsBar.frame = NSRect(
            x: max(12, bounds.midX - width / 2),
            y: bounds.maxY - height - 18,
            width: width,
            height: height
        )
        selectionOptionsStack.frame = selectionOptionsBar.bounds
    }

    private func annotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        switch tool {
        case .rectangle:
            return .rectangle(SelectionRect(start: start, end: end).rect, annotationColor, 3)
        case .arrow:
            return .arrow(from: start, to: end, annotationColor, 3)
        case .pencil:
            return .pencil(pencilPoints.isEmpty ? [start, end] : pencilPoints, annotationColor, 3)
        case .text:
            return .text(
                rect: CGRect(x: start.x, y: start.y, width: 80, height: 26),
                text: "",
                color: annotationColor,
                fontSize: annotationTextSize.fontSize
            )
        case .number:
            return .number(
                center: numberCenter(for: end),
                value: document.nextSequenceNumber,
                color: annotationColor,
                diameter: 28
            )
        case .mosaic:
            return .mosaic(SelectionRect(start: start, end: end).rect, pixelSize: 16)
        case .mosaicPencil:
            return .mosaicPencil(pencilPoints.isEmpty ? [start, end] : pencilPoints, width: 20)
        }
    }

    private func draw(_ annotation: Annotation) {
        let color: RGBAColor
        let width: CGFloat
        switch annotation {
        case let .rectangle(rect, value, lineWidth):
            color = value; width = lineWidth
            setStroke(color, width: width)
            NSBezierPath(rect: rect).stroke()
        case let .arrow(from, to, value, lineWidth):
            color = value; width = lineWidth
            setStroke(color, width: width)
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.stroke()
            let angle = atan2(to.y - from.y, to.x - from.x)
            let length = max(10, width * 4)
            let spread = CGFloat.pi / 7
            let head = NSBezierPath()
            head.move(to: CGPoint(x: to.x - length * cos(angle - spread), y: to.y - length * sin(angle - spread)))
            head.line(to: to)
            head.line(to: CGPoint(x: to.x - length * cos(angle + spread), y: to.y - length * sin(angle + spread)))
            head.stroke()
        case let .pencil(points, value, lineWidth):
            color = value; width = lineWidth
            guard let first = points.first else { return }
            setStroke(color, width: width)
            let path = NSBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            path.stroke()
        case let .text(rect, text, color, fontSize):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            AnnotationRenderer.drawText(
                text,
                rect: rect,
                color: color,
                fontSize: fontSize,
                in: context
            )
        case let .number(center, value, color, diameter):
            let badgeRect = NSRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            ).setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let digits = String(value)
            let fontScale: CGFloat = digits.count >= 3 ? 0.38 : digits.count == 2 ? 0.45 : 0.52
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: diameter * fontScale, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = digits.size(withAttributes: attributes)
            digits.draw(
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                withAttributes: attributes
            )
        case let .mosaic(rect, _):
            guard let mosaicNSImage else { return }
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            mosaicNSImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.current?.restoreGraphicsState()
        case let .mosaicPencil(points, width):
            guard let mosaicNSImage, let first = points.first, let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.setLineWidth(max(1, width))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            mosaicNSImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            context.restoreGState()
        }
    }

    private func numberCenter(for point: CGPoint) -> CGPoint {
        let radius: CGFloat = 14
        let x = selectionRect.width >= radius * 2
            ? min(max(selectionRect.minX + radius, point.x), selectionRect.maxX - radius)
            : selectionRect.midX
        let y = selectionRect.height >= radius * 2
            ? min(max(selectionRect.minY + radius, point.y), selectionRect.maxY - radius)
            : selectionRect.midY
        return CGPoint(
            x: x,
            y: y
        )
    }

    private var selectedTextRect: CGRect? {
        guard let index = selectedTextIndex,
              document.annotations.indices.contains(index)
        else { return nil }
        let annotation = textTransformPreview ?? document.annotations[index]
        guard case let .text(rect, _, _, _) = annotation else { return nil }
        return rect
    }

    private func textAnnotationIndex(at point: CGPoint) -> Int? {
        document.annotations.indices.reversed().first { index in
            guard case let .text(rect, _, _, _) = document.annotations[index] else {
                return false
            }
            return rect.insetBy(dx: -5, dy: -5).contains(point)
        }
    }

    private func selectText(at index: Int) {
        guard document.annotations.indices.contains(index),
              case let .text(_, _, color, fontSize) = document.annotations[index]
        else { return }
        selectedTextIndex = index
        annotationColor = color
        annotationTextSize = TextAnnotationSizePreset.closest(to: fontSize)
        updateTextStyleControls()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func clearTextSelection() {
        selectedTextIndex = nil
        activeTextResize = nil
        activeTextMove = nil
        textTransformPreview = nil
        window?.invalidateCursorRects(for: self)
    }

    private func textResizeHandleRect(
        handle: TextAnnotationHandle,
        in rect: CGRect
    ) -> CGRect {
        let center = CGPoint(
            x: handle.horizontalEdge == .left ? rect.minX : rect.maxX,
            y: handle == .topLeft || handle == .topRight ? rect.maxY : rect.minY
        )
        return CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
    }

    private func textResizeHandle(at point: CGPoint) -> TextAnnotationHandle? {
        guard let rect = selectedTextRect else { return nil }
        return TextAnnotationHandle.allCases.first { handle in
            textResizeHandleRect(handle: handle, in: rect)
                .insetBy(dx: -4, dy: -4)
                .contains(point)
        }
    }

    private func resizedTextAnnotation(
        _ annotation: Annotation,
        handle: TextAnnotationHandle,
        to point: CGPoint
    ) -> Annotation {
        guard case let .text(rect, text, color, fontSize) = annotation else {
            return annotation
        }
        var resized = TextAnnotationLayout.resize(
            rect,
            handle: handle,
            to: point,
            inside: selectionRect,
            minimumWidth: 48
        )
        let top = rect.maxY
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: resized.width,
            fontSize: fontSize
        )
        resized.origin.y = max(selectionRect.minY, top - height)
        resized.size.height = min(height, top - resized.minY)
        return .text(rect: resized, text: text, color: color, fontSize: fontSize)
    }

    private func movedTextAnnotation(_ annotation: Annotation, by offset: CGSize) -> Annotation {
        guard case let .text(rect, text, color, fontSize) = annotation else {
            return annotation
        }
        return .text(
            rect: TextAnnotationLayout.move(rect, by: offset, inside: selectionRect),
            text: text,
            color: color,
            fontSize: fontSize
        )
    }

    private func drawSelectedTextBox() {
        guard let rect = selectedTextRect else { return }
        let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        outline.lineWidth = 1
        outline.setLineDash([2, 3], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.82).setStroke()
        outline.stroke()
        for handle in TextAnnotationHandle.allCases {
            NSColor.white.setFill()
            NSColor.systemGray.setStroke()
            let path = NSBezierPath(ovalIn: textResizeHandleRect(handle: handle, in: rect))
            path.lineWidth = 2
            path.fill()
            path.stroke()
        }
    }

    private func beginTextEditing(at point: CGPoint, index: Int? = nil) {
        commitTextEditing()
        clearTextSelection()

        var text = ""
        var textRect: CGRect
        var selectsExistingText = false
        if let index,
           document.annotations.indices.contains(index),
           case let .text(rect, existingText, color, fontSize) = document.annotations[index] {
            text = existingText
            textRect = rect
            annotationColor = color
            annotationTextSize = TextAnnotationSizePreset.closest(to: fontSize)
            activeTextEditingIndex = index
            activeTextWidthWasAdjusted = true
            selectsExistingText = true
            updateTextStyleControls()
        } else {
            let fontSize = annotationTextSize.fontSize
            let font = NSFont.systemFont(ofSize: fontSize)
            let verticalPadding: CGFloat = 4
            let minimumBaseline = selectionRect.minY - font.descender + verticalPadding
            let maximumBaseline = selectionRect.maxY - font.ascender - verticalPadding
            let baselineY = minimumBaseline <= maximumBaseline
                ? min(max(minimumBaseline, point.y), maximumBaseline)
                : selectionRect.midY
            let textWidth: CGFloat = 160
            let textHeight = AnnotationRenderer.suggestedTextBoxHeight(
                for: " ",
                width: textWidth,
                fontSize: fontSize
            )
            textRect = TextAnnotationLayout.initialRect(
                at: CGPoint(x: point.x, y: baselineY + font.descender),
                inside: selectionRect,
                preferredWidth: textWidth,
                minimumWidth: 48,
                height: textHeight
            )
            activeTextEditingIndex = nil
            activeTextWidthWasAdjusted = false
        }

        let editor = TextAnnotationEditorView(
            frame: .zero,
            font: .systemFont(ofSize: annotationTextSize.fontSize),
            color: nsColor(annotationColor)
        )
        editor.text = text
        editor.onTextChange = { [weak self] text in
            self?.updateActiveTextEditorLayout(for: text)
        }
        editor.onCommit = { [weak self] in
            self?.commitTextEditing()
        }
        editor.onCancel = { [weak self] in
            self?.cancelTextEditing()
        }
        editor.onTransformBegan = { [weak self] in
            self?.activeTextTransformOrigin = self?.activeTextRect
        }
        editor.onResize = { [weak self] handle, point in
            self?.resizeActiveTextEditor(handle: handle, to: point)
        }
        editor.onMove = { [weak self] offset in
            self?.moveActiveTextEditor(by: offset)
        }
        editor.onTransformEnded = { [weak self] in
            self?.activeTextTransformOrigin = nil
        }
        activeTextEditor = editor
        activeTextRect = textRect
        addSubview(editor)
        editor.update(annotationRect: textRect)
        editor.focus(selectAll: selectsExistingText)
        needsDisplay = true
    }

    private func updateActiveTextEditorLayout(for text: String) {
        guard let editor = activeTextEditor, var rect = activeTextRect else { return }
        let font = NSFont.systemFont(ofSize: annotationTextSize.fontSize)
        if !activeTextWidthWasAdjusted {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let widestLine = text
                .components(separatedBy: .newlines)
                .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
                .max() ?? 0
            let maximumWidth = max(48, selectionRect.maxX - rect.minX)
            rect.size.width = min(maximumWidth, max(96, min(220, widestLine + 16)))
        }
        let top = rect.maxY
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: rect.width,
            fontSize: annotationTextSize.fontSize
        )
        rect.origin.y = max(selectionRect.minY, top - height)
        rect.size.height = min(height, top - rect.minY)
        activeTextRect = rect
        editor.update(annotationRect: rect)
    }

    private func resizeActiveTextEditor(handle: TextAnnotationHandle, to point: CGPoint) {
        guard let editor = activeTextEditor,
              let currentRect = activeTextRect
        else { return }
        let original = activeTextTransformOrigin ?? currentRect
        var resized = TextAnnotationLayout.resize(
            original,
            handle: handle,
            to: point,
            inside: selectionRect,
            minimumWidth: 48
        )
        let top = original.maxY
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: editor.text,
            width: resized.width,
            fontSize: annotationTextSize.fontSize
        )
        resized.origin.y = max(selectionRect.minY, top - height)
        resized.size.height = min(height, top - resized.minY)
        activeTextWidthWasAdjusted = true
        activeTextRect = resized
        editor.update(annotationRect: resized)
    }

    private func moveActiveTextEditor(by offset: CGSize) {
        guard let editor = activeTextEditor,
              let currentRect = activeTextRect
        else { return }
        let original = activeTextTransformOrigin ?? currentRect
        let moved = TextAnnotationLayout.move(original, by: offset, inside: selectionRect)
        activeTextRect = moved
        editor.update(annotationRect: moved)
    }

    private func commitTextEditing() {
        guard let editor = activeTextEditor, var rect = activeTextRect else { return }
        let text = editor.text
        let editingIndex = activeTextEditingIndex
        activeTextEditor = nil
        activeTextRect = nil
        activeTextEditingIndex = nil
        activeTextTransformOrigin = nil
        activeTextWidthWasAdjusted = false
        editor.onTextChange = nil
        editor.onCommit = nil
        editor.onCancel = nil
        editor.removeFromSuperview()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let editingIndex {
                _ = document.remove(at: editingIndex)
                selectedTextIndex = nil
            }
        } else {
            let top = rect.maxY
            let height = AnnotationRenderer.suggestedTextBoxHeight(
                for: text,
                width: rect.width,
                fontSize: annotationTextSize.fontSize
            )
            rect.origin.y = max(selectionRect.minY, top - height)
            rect.size.height = min(height, top - rect.minY)
            let annotation = Annotation.text(
                rect: rect,
                text: text,
                color: annotationColor,
                fontSize: annotationTextSize.fontSize
            )
            if let editingIndex {
                _ = document.replace(at: editingIndex, with: annotation)
                selectedTextIndex = editingIndex
            } else {
                document.append(annotation)
                selectedTextIndex = document.annotations.count - 1
            }
            window?.invalidateCursorRects(for: self)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelTextEditing() {
        guard let editor = activeTextEditor else { return }
        activeTextEditor = nil
        activeTextRect = nil
        activeTextEditingIndex = nil
        activeTextTransformOrigin = nil
        activeTextWidthWasAdjusted = false
        editor.onTextChange = nil
        editor.onCommit = nil
        editor.onCancel = nil
        editor.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func setStroke(_ color: RGBAColor, width: CGFloat) {
        nsColor(color).setStroke()
        NSBezierPath.defaultLineWidth = width
        NSBezierPath.defaultLineCapStyle = .round
        NSBezierPath.defaultLineJoinStyle = .round
    }

    private func nsColor(_ color: RGBAColor) -> NSColor {
        NSColor(
            srgbRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    private func finish(_ action: CaptureResultAction) {
        commitTextEditing()
        if case .recordGIF = action {
            onResult(
                CaptureResult(
                    image: screenshot,
                    annotations: [],
                    selectionRect: selectionRect,
                    windowID: nil,
                    action: action
                )
            )
            return
        }
        if case .scrollCapture = action {
            onResult(
                CaptureResult(
                    image: screenshot,
                    annotations: [],
                    selectionRect: selectionRect,
                    windowID: nil,
                    action: action
                )
            )
            return
        }
        let scale = CGFloat(screenshot.width) / max(1, bounds.width)
        let mapper = DisplayCoordinateMapper(viewHeight: bounds.height, pixelScale: scale)
        let imageBounds = CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height)
        let cropRect = mapper.pixelRect(for: selectionRect).intersection(imageBounds)
        guard !cropRect.isEmpty, let crop = screenshot.cropping(to: cropRect) else {
            NSSound.beep()
            return
        }
        let mapped = document.annotations.map {
            $0.mapped(relativeTo: selectionRect.origin, scale: scale)
        }
        onResult(
            CaptureResult(
                image: crop,
                annotations: mapped,
                selectionRect: selectionRect,
                windowID: selectionState.selectedApplicationWindowID(matching: selectionRect),
                action: action
            )
        )
    }

    private func drawSizeLabel() {
        let label = "\(Int(round(selectionRect.width))) × \(Int(round(selectionRect.height)))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attributes)
        var origin = CGPoint(x: selectionRect.minX + 4, y: selectionRect.maxY + 7)
        if origin.y + size.height + 8 > bounds.maxY {
            origin.y = selectionRect.maxY - size.height - 8
        }
        let background = NSRect(x: origin.x - 4, y: origin.y - 3, width: size.width + 8, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        label.draw(at: origin, withAttributes: attributes)
    }

    private func drawCrosshair(at point: CGPoint) {
        NSColor.white.withAlphaComponent(0.72).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: point.x - 10, y: point.y))
        path.line(to: CGPoint(x: point.x + 10, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 10))
        path.line(to: CGPoint(x: point.x, y: point.y + 10))
        path.stroke()
    }

    private func bounded(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(bounds.minX, point.x), bounds.maxX), y: min(max(bounds.minY, point.y), bounds.maxY))
    }
}
