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
    private var selectedNumberIndex: Int?
    private var selectedTextIndex: Int?
    private var activeTextResize: (
        index: Int,
        handle: TextAnnotationHandle,
        startPoint: CGPoint,
        original: Annotation
    )?
    private var activeTextMove: (
        index: Int,
        startPoint: CGPoint,
        original: Annotation
    )?
    private var textTransformPreview: Annotation?
    private var textDragHasStarted = false
    private var selectedRectangleIndex: Int?
    private var activeRectangleResize: (
        index: Int,
        handle: SelectionResizeHandle,
        original: Annotation
    )?
    private var activeRectangleMove: (
        index: Int,
        startPoint: CGPoint,
        original: Annotation
    )?
    private var rectangleTransformPreview: Annotation?
    private var document = AnnotationDocument() {
        didSet { updateHistoryControls() }
    }
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
    private let toolsStack = NSStackView()
    private let actionsStack = NSStackView()
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private let selectionOptionsBar = NSView()
    private let selectionOptionsStack = NSStackView()
    private let aspectRatioPopUp = NSPopUpButton()
    private var aspectRatioOption = AspectRatioOption.free
    private var toolButtons: [Tool: NSButton] = [:]
    private let arrowOptionsBar = NSView()
    private let arrowOptionsStack = NSStackView()
    private var arrowStyleButtons: [ArrowAnnotationStyle: NSButton] = [:]
    private var annotationArrowStyle = ArrowAnnotationStyle.line
    private let numberOptionsBar = NSView()
    private let numberOptionsStack = NSStackView()
    private let numberSizePopUp = NSPopUpButton()
    private var annotationNumberSize = NumberAnnotationSizePreset.medium
    private let textOptionsBar = NSView()
    private let textOptionsStack = NSStackView()
    private let textSizePopUp = NSPopUpButton()
    private let textHint = NSTextField(labelWithString: "拖边框移动 · 两侧调宽 · ⌘↩ 完成")
    private var textColorSwatches: [NSButton] = []
    private var annotationColor = TextAnnotationPalette.colors.last!
    private var annotationTextSize = TextAnnotationSizePreset.medium
    private var cachedSizeLabelInfo: (text: String, size: CGSize)?
    private static let sizeLabelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let sizeLabelAttributes: [NSAttributedString.Key: Any] = [
        .font: sizeLabelFont,
        .foregroundColor: NSColor.white
    ]
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
        configureNumberOptionsBar()
        configureArrowOptionsBar()
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

        if tool == .text {
            addCursorRect(selectionRect, cursor: .iBeam)
            for annotation in document.annotations {
                if case let .text(rect, _, _, _) = annotation {
                    addCursorRect(rect.insetBy(dx: -TextAnnotationLayout.borderHitWidth,
                                              dy: -TextAnnotationLayout.borderHitWidth), cursor: .openHand)
                }
            }
        }
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
                    TextAnnotationLayout.handleRect(handle, in: rect, hitArea: true),
                    cursor: Self.leftRightResizeCursor
                )
            }
        }
        if let rect = selectedRectangleRect {
            addCursorRect(rect, cursor: .openHand)
            for handle in SelectionResizeHandle.allCases {
                let center = SelectionAdjustment.center(of: handle, in: rect)
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
        layoutNumberOptionsBar()
        layoutArrowOptionsBar()
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
            } else if index == selectedRectangleIndex, let rectangleTransformPreview {
                draw(rectangleTransformPreview)
            } else if index == selectedTextIndex, let textTransformPreview {
                draw(textTransformPreview)
            } else {
                draw(annotation)
            }
        }
        if let currentAnnotation {
            draw(currentAnnotation)
        }
        drawSelectedNumberBox()
        drawSelectedTextBox()
        drawSelectedRectangleBox()
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
            textDragHasStarted = false
            if tool == .number, let index = numberAnnotationIndex(at: point),
               case let .number(_, _, _, diameter) = document.annotations[index] {
                selectedNumberIndex = index
                annotationNumberSize = .closest(to: diameter)
                numberSizePopUp.selectItem(at: annotationNumberSize.rawValue)
                needsDisplay = true
                return
            }
            selectedNumberIndex = nil
            if let handle = rectangleResizeHandle(at: point),
               let index = selectedRectangleIndex,
               document.annotations.indices.contains(index) {
                activeRectangleResize = (index, handle, document.annotations[index])
                activeRectangleMove = nil
                rectangleTransformPreview = document.annotations[index]
                annotationStart = nil
                currentAnnotation = nil
                pencilPoints.removeAll()
                return
            }
            if let handle = textResizeHandle(at: point),
               let index = selectedTextIndex,
               document.annotations.indices.contains(index) {
                activeTextResize = (index, handle, point, document.annotations[index])
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
            if tool == .rectangle,
               let index = rectangleAnnotationIndex(at: point) {
                selectRectangle(at: index)
                activeRectangleMove = (index, point, document.annotations[index])
                rectangleTransformPreview = document.annotations[index]
                return
            }
            clearTextSelection()
            clearRectangleSelection()
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
            if let activeRectangleResize {
                rectangleTransformPreview = RectangleAnnotationLayout.resize(
                    activeRectangleResize.original,
                    using: activeRectangleResize.handle,
                    to: point,
                    inside: selectionRect,
                    minimumDimension: 8
                )
                needsDisplay = true
                return
            }
            if let activeRectangleMove {
                rectangleTransformPreview = RectangleAnnotationLayout.move(
                    activeRectangleMove.original,
                    by: CGSize(
                        width: point.x - activeRectangleMove.startPoint.x,
                        height: point.y - activeRectangleMove.startPoint.y
                    ),
                    inside: selectionRect
                )
                needsDisplay = true
                return
            }
            if let activeTextResize {
                guard textDragHasStarted || TextAnnotationLayout.hasDragged(from: activeTextResize.startPoint, to: point),
                      case let .text(rect, _, _, _) = activeTextResize.original else { return }
                textDragHasStarted = true
                NSCursor.resizeLeftRight.set()
                let target = TextAnnotationLayout.resizePoint(for: activeTextResize.handle, in: rect,
                                                            from: activeTextResize.startPoint, to: point)
                textTransformPreview = resizedTextAnnotation(
                    activeTextResize.original,
                    handle: activeTextResize.handle,
                    to: target
                )
                needsDisplay = true
                return
            }
            if let activeTextMove {
                guard textDragHasStarted || TextAnnotationLayout.hasDragged(from: activeTextMove.startPoint, to: point) else { return }
                textDragHasStarted = true
                NSCursor.closedHand.set()
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
            numberOptionsBar.isHidden = tool != .number
            arrowOptionsBar.isHidden = tool != .arrow
            selectionOptionsBar.isHidden = true
            updateToolButtons()
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        case .editing:
            if let activeRectangleResize {
                if let rectangleTransformPreview {
                    _ = document.replace(
                        at: activeRectangleResize.index,
                        with: rectangleTransformPreview
                    )
                }
                selectedRectangleIndex = activeRectangleResize.index
                self.activeRectangleResize = nil
                rectangleTransformPreview = nil
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            if let activeRectangleMove {
                if let rectangleTransformPreview {
                    _ = document.replace(
                        at: activeRectangleMove.index,
                        with: rectangleTransformPreview
                    )
                }
                selectedRectangleIndex = activeRectangleMove.index
                self.activeRectangleMove = nil
                rectangleTransformPreview = nil
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            if let activeTextResize {
                if let textTransformPreview {
                    _ = document.replace(at: activeTextResize.index, with: textTransformPreview)
                }
                selectedTextIndex = activeTextResize.index
                self.activeTextResize = nil
                textTransformPreview = nil
                NSCursor.resizeLeftRight.set()
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
                NSCursor.openHand.set()
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
                if case .number = currentAnnotation {
                    selectedNumberIndex = document.annotations.count - 1
                }
                if case .rectangle = currentAnnotation {
                    selectedRectangleIndex = document.annotations.count - 1
                    window?.invalidateCursorRects(for: self)
                }
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
            if let index = selectedNumberIndex, document.remove(at: index) {
                selectedNumberIndex = nil
                needsDisplay = true
                return
            }
            if deleteSelectedTextAnnotation() { return }
        }
        if event.keyCode == 53 {
            onCancel()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            clearTextSelection()
            clearRectangleSelection()
            selectedNumberIndex = nil
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

        // Refactoring UI §3.6: separate annotation tools from output actions.
        defer {
            toolsStack.setFrameSize(toolsStack.fittingSize)
            actionsStack.setFrameSize(actionsStack.fittingSize)
        }
        for group in [toolsStack, actionsStack] {
            group.orientation = .horizontal
            group.alignment = .centerY
            group.spacing = CaptureToolbarStyle.itemSpacing
            group.setContentHuggingPriority(.required, for: .horizontal)
        }
        if purpose == .stillImage { toolbar.addSubview(toolsStack) }
        toolbar.addSubview(actionsStack)
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
        let undo = button(symbol: "arrow.uturn.backward", help: "撤销（⌘Z）", tag: 10)
        let redo = button(symbol: "arrow.uturn.forward", help: "重做（⇧⌘Z）", tag: 11)
        undoButton = undo
        redoButton = redo
        actionsStack.addArrangedSubview(undo)
        actionsStack.addArrangedSubview(redo)
        actionsStack.addArrangedSubview(separator())
        updateHistoryControls()
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

        selectionOptionsStack.setFrameSize(selectionOptionsStack.fittingSize)
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
        toolsStack.addArrangedSubview(control)
    }

    private func addTextToolButton() {
        let control = button(image: Self.makeTextToolImage(), help: "文字", tag: Tool.text.rawValue)
        control.setButtonType(.toggle)
        toolButtons[.text] = control
        toolsStack.addArrangedSubview(control)
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

    private func configureArrowOptionsBar() {
        arrowOptionsBar.appearance = NSAppearance(named: .aqua)
        arrowOptionsBar.wantsLayer = true
        arrowOptionsBar.layer?.backgroundColor = NSColor.white.cgColor
        arrowOptionsBar.layer?.cornerRadius = 10
        arrowOptionsBar.layer?.borderWidth = 0.5
        arrowOptionsBar.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        arrowOptionsBar.isHidden = true
        arrowOptionsStack.orientation = .horizontal
        arrowOptionsStack.alignment = .centerY
        arrowOptionsStack.spacing = 6
        arrowOptionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let label = NSTextField(labelWithString: "箭头样式")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        arrowOptionsStack.addArrangedSubview(label)
        for style in ArrowAnnotationStyle.allCases {
            let image = NSImage(size: NSSize(width: 36, height: 24), flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                AnnotationRenderer.drawArrow(from: CGPoint(x: 4, y: 6), to: CGPoint(x: 32, y: 18),
                    color: RGBAColor(red: 0, green: 0, blue: 0), width: 1.8, style: style, in: context)
                return true
            }
            image.isTemplate = true
            let control = NSButton(image: image, target: self, action: #selector(arrowStyleChanged(_:)))
            control.setButtonType(.toggle)
            control.isBordered = false
            control.imagePosition = .imageOnly
            control.alignment = .center
            control.tag = style.rawValue
            control.toolTip = style.title
            control.setAccessibilityLabel(style.title)
            control.wantsLayer = true
            control.layer?.cornerRadius = 6
            control.widthAnchor.constraint(equalToConstant: 44).isActive = true
            control.heightAnchor.constraint(equalToConstant: 32).isActive = true
            arrowStyleButtons[style] = control
            arrowOptionsStack.addArrangedSubview(control)
        }
        updateArrowStyleControls()
        arrowOptionsBar.addSubview(arrowOptionsStack)
        addSubview(arrowOptionsBar)
    }

    @objc private func arrowStyleChanged(_ sender: NSButton) {
        guard let style = ArrowAnnotationStyle(rawValue: sender.tag) else { return }
        annotationArrowStyle = style
        updateArrowStyleControls()
    }

    private func updateArrowStyleControls() {
        for (style, control) in arrowStyleButtons {
            let selected = style == annotationArrowStyle
            control.state = selected ? .on : .off
            control.contentTintColor = .labelColor
            control.layer?.backgroundColor = selected ? NSColor.black.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
            control.layer?.borderWidth = selected ? 1 : 0
            control.layer?.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
        }
    }

    private func layoutArrowOptionsBar() {
        guard !arrowOptionsBar.isHidden else { return }
        let size = arrowOptionsStack.fittingSize
        let center = toolButtons[.arrow].map { convert($0.bounds, from: $0).midX } ?? toolbar.frame.midX
        arrowOptionsBar.frame = CaptureToolbarLayout.frame(size: size, beside: toolbar.frame, in: bounds,
            preferredCenterX: center, prefersBelow: toolbar.frame.midY < selectionRect.midY)
        arrowOptionsStack.frame = arrowOptionsBar.bounds
    }

    private func configureNumberOptionsBar() {
        numberOptionsBar.appearance = NSAppearance(named: .aqua)
        numberOptionsBar.wantsLayer = true
        numberOptionsBar.layer?.backgroundColor = NSColor.white.cgColor
        numberOptionsBar.layer?.cornerRadius = 10
        numberOptionsBar.layer?.borderWidth = 0.5
        numberOptionsBar.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        numberOptionsBar.isHidden = true
        numberOptionsStack.orientation = .horizontal
        numberOptionsStack.alignment = .centerY
        numberOptionsStack.spacing = 8
        numberOptionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let label = NSTextField(labelWithString: "序号大小")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        numberOptionsStack.addArrangedSubview(label)
        numberSizePopUp.addItems(withTitles: NumberAnnotationSizePreset.allCases.map(\.title))
        numberSizePopUp.selectItem(at: annotationNumberSize.rawValue)
        numberSizePopUp.toolTip = "序号大小"
        numberSizePopUp.setAccessibilityLabel("序号大小")
        numberSizePopUp.target = self
        numberSizePopUp.action = #selector(numberSizeChanged(_:))
        numberSizePopUp.widthAnchor.constraint(equalToConstant: 64).isActive = true
        numberOptionsStack.addArrangedSubview(numberSizePopUp)
        let hint = NSTextField(labelWithString: "点击已有序号可调整")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        numberOptionsStack.addArrangedSubview(hint)
        numberOptionsStack.setFrameSize(numberOptionsStack.fittingSize)
        numberOptionsBar.addSubview(numberOptionsStack)
        addSubview(numberOptionsBar)
    }

    @objc private func numberSizeChanged(_ sender: NSPopUpButton) {
        guard let preset = NumberAnnotationSizePreset(rawValue: sender.indexOfSelectedItem) else { return }
        annotationNumberSize = preset
        if let index = selectedNumberIndex, document.annotations.indices.contains(index),
           case let .number(center, value, color, _) = document.annotations[index] {
            _ = document.replace(at: index, with: .number(center: numberCenter(for: center),
                                                          value: value, color: color, diameter: numberDiameter))
        }
        needsDisplay = true
    }

    private func numberAnnotationIndex(at point: CGPoint) -> Int? {
        document.annotations.indices.reversed().first { index in
            guard case let .number(center, _, _, diameter) = document.annotations[index] else { return false }
            return hypot(point.x - center.x, point.y - center.y) <= diameter / 2
        }
    }

    private func drawSelectedNumberBox() {
        guard let index = selectedNumberIndex, document.annotations.indices.contains(index),
              case let .number(center, _, _, diameter) = document.annotations[index] else { return }
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - diameter / 2 - 3,
            y: center.y - diameter / 2 - 3, width: diameter + 6, height: diameter + 6))
        NSColor.white.setStroke()
        ring.lineWidth = 3
        ring.stroke()
        NSColor.black.setStroke()
        ring.lineWidth = 1
        ring.setLineDash([3, 3], count: 2, phase: 0)
        ring.stroke()
    }

    private func layoutNumberOptionsBar() {
        guard !numberOptionsBar.isHidden else { return }
        let size = numberOptionsStack.fittingSize
        let center = toolButtons[.number].map { convert($0.bounds, from: $0).midX } ?? toolbar.frame.midX
        numberOptionsBar.frame = CaptureToolbarLayout.frame(size: size, beside: toolbar.frame, in: bounds,
            preferredCenterX: center, prefersBelow: toolbar.frame.midY < selectionRect.midY)
        numberOptionsStack.frame = numberOptionsBar.bounds
    }

    private func configureTextOptionsBar() {
        textOptionsBar.appearance = NSAppearance(named: .aqua)
        textOptionsBar.wantsLayer = true
        textOptionsBar.layer?.backgroundColor = NSColor.white.cgColor
        textOptionsBar.layer?.cornerRadius = 10
        textOptionsBar.layer?.borderWidth = 0.5
        textOptionsBar.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        textOptionsBar.layer?.shadowColor = NSColor.black.cgColor
        textOptionsBar.layer?.shadowOpacity = 0.2
        textOptionsBar.layer?.shadowRadius = 8
        textOptionsBar.layer?.shadowOffset = CGSize(width: 0, height: -2)
        textOptionsBar.isHidden = true

        textOptionsStack.orientation = .horizontal
        textOptionsStack.alignment = .centerY
        textOptionsStack.spacing = 7
        textOptionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let sizeLabel = NSTextField(labelWithString: "字号")
        sizeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        textOptionsStack.addArrangedSubview(sizeLabel)
        textSizePopUp.setAccessibilityLabel("文字大小")
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
            swatch.toolTip = "文字颜色：" + TextAnnotationPalette.colorNames[index]
            swatch.setAccessibilityLabel(swatch.toolTip)
            swatch.setButtonType(.toggle)
            swatch.imagePosition = .imageOnly
            swatch.widthAnchor.constraint(equalToConstant: 30).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 30).isActive = true
            textColorSwatches.append(swatch)
            textOptionsStack.addArrangedSubview(swatch)
        }

        textOptionsStack.setFrameSize(textOptionsStack.fittingSize)
        textOptionsBar.addSubview(textOptionsStack)
        textHint.font = .systemFont(ofSize: 11)
        textHint.textColor = .secondaryLabelColor
        textOptionsBar.addSubview(textHint)
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
            stylePrimaryAction(control, title: "复制")
        case .save:
            control = button(
                symbol: "square.and.arrow.down",
                help: "保存分享图",
                tag: action.rawValue
            )
        case .pin:
            control = button(
                symbol: "pin",
                help: "贴图到屏幕",
                tag: action.rawValue
            )
        case .recordGIF:
            control = button(
                symbol: "record.circle.fill",
                help: "开始录制 GIF",
                tag: action.rawValue
            )
            stylePrimaryAction(control, title: "录制")
        case .scrollCapture:
            control = button(
                symbol: "rectangle.stack",
                help: "滚动截屏",
                tag: action.rawValue
            )
            if purpose == .scrollingCapture { stylePrimaryAction(control, title: "开始") }
        case .cancel:
            control = button(
                symbol: "xmark",
                help: "取消",
                tag: action.rawValue
            )
        }
        actionsStack.addArrangedSubview(control)
    }

    private func stylePrimaryAction(_ control: NSButton, title: String) {
        // §2.8: one primary action; cancellation does not need a danger color.
        control.title = title
        control.imagePosition = .imageLeading
        control.imageHugsTitle = true
        control.alignment = .center
        control.font = .systemFont(ofSize: 12, weight: .semibold)
        control.contentTintColor = .white
        control.layer?.backgroundColor = NSColor.black.cgColor
        control.constraints.first { $0.firstAttribute == .width }?.constant = 68
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
        control.setAccessibilityLabel(help)
        control.contentTintColor = .labelColor
        control.wantsLayer = true
        control.layer?.cornerRadius = CaptureToolbarStyle.controlRadius
        control.widthAnchor.constraint(equalToConstant: CaptureToolbarStyle.controlSize).isActive = true
        control.heightAnchor.constraint(equalToConstant: CaptureToolbarStyle.controlSize).isActive = true
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
            if selectedTool != .number { selectedNumberIndex = nil }
            if selectedTool != .text { clearTextSelection() }
            if selectedTool != .rectangle { clearRectangleSelection() }
            textOptionsBar.isHidden = selectedTool != .text
            numberOptionsBar.isHidden = selectedTool != .number
            arrowOptionsBar.isHidden = selectedTool != .arrow
            updateToolButtons()
            needsLayout = true
            needsDisplay = true
            return
        }
        switch sender.tag {
        case 10:
            commitTextEditing(); clearTextSelection(); clearRectangleSelection(); selectedNumberIndex = nil; document.undo(); needsDisplay = true
        case 11:
            commitTextEditing(); clearTextSelection(); clearRectangleSelection(); selectedNumberIndex = nil; document.redo(); needsDisplay = true
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
            let selected = candidate == tool
            button.state = selected ? .on : .off
            // §5.7: a persistent shape, not only a different icon color.
            button.contentTintColor = .labelColor
            button.layer?.backgroundColor = selected ? NSColor.white.cgColor : NSColor.clear.cgColor
            button.layer?.borderWidth = selected ? 1 : 0
            button.layer?.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
        }
    }

    private func updateHistoryControls() {
        let pendingText = activeTextEditor.map {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeTextEditingIndex != nil
        } ?? false
        undoButton?.isEnabled = document.canUndo || pendingText
        redoButton?.isEnabled = document.canRedo && !pendingText
        undoButton?.contentTintColor = undoButton?.isEnabled == true ? .labelColor : .disabledControlTextColor
        redoButton?.contentTintColor = redoButton?.isEnabled == true ? .labelColor : .disabledControlTextColor
    }

    private func updateTextStyleControls() {
        textSizePopUp.selectItem(at: annotationTextSize.rawValue)
        for (index, swatch) in textColorSwatches.enumerated() {
            let selected = TextAnnotationPalette.colors[index] == annotationColor
            swatch.state = selected ? .on : .off
            // §5.6 / §5.7: white remains visible, and selection carries a checkmark.
            swatch.layer?.borderWidth = 1
            swatch.layer?.borderColor = NSColor.black.withAlphaComponent(0.45).cgColor
            swatch.image = selected ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已选择") : nil
            swatch.contentTintColor = index == 3 ? .white : .black
        }
    }

    private func applySelectedTextStyle() {
        guard let index = selectedTextIndex,
              document.annotations.indices.contains(index),
              case let .text(rect, text, _, _) = document.annotations[index]
        else { return }
        var updatedRect = rect
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: rect.width,
            fontSize: annotationTextSize.fontSize
        )
        updatedRect = TextAnnotationLayout.fittingHeight(updatedRect, height: height, inside: selectionRect)
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
        let toolsSize = toolsStack.fittingSize
        let actionsSize = actionsStack.fittingSize
        let grouped = purpose == .stillImage
        let horizontalWidth = (grouped ? toolsSize.width + CaptureToolbarStyle.groupSpacing : 0)
            + actionsSize.width + 16
        let wraps = grouped && horizontalWidth > bounds.width - CaptureToolbarStyle.screenInset * 2
        let size = CGSize(
            width: wraps ? max(toolsSize.width, actionsSize.width) + 16 : horizontalWidth,
            height: (wraps ? toolsSize.height + CaptureToolbarStyle.groupSpacing : 0) + actionsSize.height + 12
        )
        toolbar.frame = CaptureToolbarLayout.frame(size: size, beside: selectionRect, in: bounds)
        toolsStack.frame = CGRect(x: 8, y: wraps ? actionsSize.height + CaptureToolbarStyle.groupSpacing + 6 : 6,
                                  width: toolsSize.width, height: toolsSize.height)
        actionsStack.frame = CGRect(x: size.width - actionsSize.width - 8, y: 6,
                                    width: actionsSize.width, height: actionsSize.height)
        toolsStack.layoutSubtreeIfNeeded()
        actionsStack.layoutSubtreeIfNeeded()
    }

    private func layoutTextOptionsBar() {
        guard !textOptionsBar.isHidden else { return }
        let desired = textOptionsStack.fittingSize
        let height = max(46, desired.height) + 22
        let textButtonCenterX = toolButtons[.text].map { convert($0.bounds, from: $0).midX } ?? toolbar.frame.midX
        // Keep both panels together on the same side when there is enough room.
        textOptionsBar.frame = CaptureToolbarLayout.frame(
            size: CGSize(width: desired.width, height: height), beside: toolbar.frame, in: bounds,
            preferredCenterX: textButtonCenterX, prefersBelow: toolbar.frame.midY < selectionRect.midY
        )
        textOptionsStack.frame = CGRect(x: 0, y: 22, width: desired.width, height: height - 22)
        textHint.frame = CGRect(x: 10, y: 8, width: desired.width - 20, height: 14)
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
            return .arrow(from: start, to: end, annotationColor, 3, style: annotationArrowStyle)
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
                diameter: numberDiameter
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
        case let .arrow(from, to, value, lineWidth, style):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            AnnotationRenderer.drawArrow(from: from, to: to, color: value, width: lineWidth,
                                         style: style, in: context)
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

    private var numberDiameter: CGFloat {
        min(annotationNumberSize.diameter, max(16, min(selectionRect.width, selectionRect.height)))
    }

    private func numberCenter(for point: CGPoint) -> CGPoint {
        let radius = numberDiameter / 2
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
            return rect.insetBy(dx: -TextAnnotationLayout.borderHitWidth, dy: -TextAnnotationLayout.borderHitWidth).contains(point)
        }
    }

    private func selectText(at index: Int) {
        guard document.annotations.indices.contains(index),
              case let .text(_, _, color, fontSize) = document.annotations[index]
        else { return }
        clearRectangleSelection()
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
        textDragHasStarted = false
        window?.invalidateCursorRects(for: self)
    }

    private func textResizeHandle(at point: CGPoint) -> TextAnnotationHandle? {
        guard let rect = selectedTextRect,
              case let .resize(handle) = TextAnnotationLayout.hitTarget(at: point, in: rect)
        else { return nil }
        return handle
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
            minimumWidth: TextAnnotationLayout.minimumWidth
        )
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: resized.width,
            fontSize: fontSize
        )
        resized = TextAnnotationLayout.fittingHeight(resized, height: height, inside: selectionRect)
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
        TextAnnotationChrome.draw(in: rect, editing: false,
                                  dragging: textDragHasStarted && (activeTextMove != nil || activeTextResize != nil))
    }

    private var selectedRectangleRect: CGRect? {
        guard let index = selectedRectangleIndex,
              document.annotations.indices.contains(index)
        else { return nil }
        let annotation = rectangleTransformPreview ?? document.annotations[index]
        guard case let .rectangle(rect, _, _) = annotation else { return nil }
        return rect
    }

    private func rectangleAnnotationIndex(at point: CGPoint) -> Int? {
        document.annotations.indices.reversed().first { index in
            RectangleAnnotationLayout.hitTest(
                point,
                annotation: document.annotations[index],
                tolerance: 5
            )
        }
    }

    private func selectRectangle(at index: Int) {
        guard document.annotations.indices.contains(index),
              case .rectangle = document.annotations[index]
        else { return }
        clearTextSelection()
        selectedRectangleIndex = index
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func clearRectangleSelection() {
        selectedRectangleIndex = nil
        activeRectangleResize = nil
        activeRectangleMove = nil
        rectangleTransformPreview = nil
        window?.invalidateCursorRects(for: self)
    }

    private func rectangleResizeHandle(at point: CGPoint) -> SelectionResizeHandle? {
        guard let rect = selectedRectangleRect else { return nil }
        return SelectionAdjustment.handle(
            at: point,
            in: rect,
            hitRadius: SelectionOverlayStyle.handleHitRadius
        )
    }

    private func drawSelectedRectangleBox() {
        guard let rect = selectedRectangleRect else { return }
        let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        outline.lineWidth = 1
        outline.setLineDash([2, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        outline.stroke()

        for handle in SelectionResizeHandle.allCases {
            let center = SelectionAdjustment.center(of: handle, in: rect)
            NSColor.white.setFill()
            NSBezierPath(
                ovalIn: SelectionOverlayStyle.handleOuterRect(centeredAt: center)
            ).fill()
            NSColor.systemBlue.setFill()
            NSBezierPath(
                ovalIn: SelectionOverlayStyle.handleInnerRect(centeredAt: center)
            ).fill()
        }
    }

    private func beginTextEditing(at point: CGPoint, index: Int? = nil) {
        commitTextEditing()
        clearTextSelection()
        clearRectangleSelection()

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
            let textWidth = TextAnnotationLayout.initialWidth
            let textHeight = AnnotationRenderer.suggestedTextBoxHeight(
                for: " ",
                width: textWidth,
                fontSize: fontSize
            )
            textRect = TextAnnotationLayout.initialRect(
                at: point,
                inside: selectionRect,
                preferredWidth: textWidth,
                minimumWidth: TextAnnotationLayout.minimumWidth,
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
            self?.updateHistoryControls()
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
        updateHistoryControls()
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
            let maximumWidth = max(1, selectionRect.maxX - rect.minX)
            let desiredWidth = min(TextAnnotationLayout.maximumAutomaticWidth,
                                   widestLine + TextAnnotationLayout.horizontalTextInset * 2)
            rect.size.width = min(maximumWidth, max(rect.width, desiredWidth))
        }
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: text,
            width: rect.width,
            fontSize: annotationTextSize.fontSize
        )
        rect = TextAnnotationLayout.fittingHeight(rect, height: height, inside: selectionRect)
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
            minimumWidth: TextAnnotationLayout.minimumWidth
        )
        let height = AnnotationRenderer.suggestedTextBoxHeight(
            for: editor.text,
            width: resized.width,
            fontSize: annotationTextSize.fontSize
        )
        resized = TextAnnotationLayout.fittingHeight(resized, height: height, inside: selectionRect)
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
            let height = AnnotationRenderer.suggestedTextBoxHeight(
                for: text,
                width: rect.width,
                fontSize: annotationTextSize.fontSize
            )
            rect = TextAnnotationLayout.fittingHeight(rect, height: height, inside: selectionRect)
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
        updateHistoryControls()
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
        updateHistoryControls()
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
        let label = "\(Int(round(selectionRect.width))) x \(Int(round(selectionRect.height)))"
        let size: CGSize
        if let cached = cachedSizeLabelInfo, cached.text == label {
            size = cached.size
        } else {
            size = label.size(withAttributes: Self.sizeLabelAttributes)
            cachedSizeLabelInfo = (label, size)
        }
        var origin = CGPoint(x: selectionRect.minX + 4, y: selectionRect.maxY + 7)
        if origin.y + size.height + 8 > bounds.maxY {
            origin.y = selectionRect.maxY - size.height - 8
        }
        let background = NSRect(x: origin.x - 4, y: origin.y - 3, width: size.width + 8, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        label.draw(at: origin, withAttributes: Self.sizeLabelAttributes)
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
