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

@MainActor
final class SelectionOverlayView: NSView {
    private enum Phase { case selecting, editing }
    private enum Tool: Int { case rectangle = 1, arrow = 2, pencil = 3, number = 4 }
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
    private let onResult: (CGImage, CGRect, CaptureResultAction) -> Void
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
    private var document = AnnotationDocument()
    private let toolbar = NSView()
    private let stack = NSStackView()
    private let selectionOptionsBar = NSView()
    private let selectionOptionsStack = NSStackView()
    private let aspectRatioPopUp = NSPopUpButton()
    private var aspectRatioOption = AspectRatioOption.free
    private var toolButtons: [Tool: NSButton] = [:]
    private let accent = RGBAColor(red: 0.98, green: 0.31, blue: 0.24)

    init(
        frame frameRect: NSRect,
        screenshot: CGImage,
        windowCandidates: [WindowCandidate],
        initialPointer: CGPoint,
        initialSelectionRect: CGRect,
        purpose: CaptureOverlayPurpose,
        onResult: @escaping (CGImage, CGRect, CaptureResultAction) -> Void,
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
        configureSelectionOptionsBar()
        toolbar.isHidden = phase == .selecting
        selectionOptionsBar.isHidden = phase == .editing
        if phase == .editing { updateToolButtons() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        layoutSelectionOptionsBar()
        layoutToolbar()
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

        for annotation in document.annotations {
            draw(annotation)
        }
        if let currentAnnotation {
            draw(currentAnnotation)
        }
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
            if let handle = SelectionAdjustment.handle(
                at: point,
                in: selectionRect,
                hitRadius: 8
            ) {
                activeResize = (handle, selectionRect)
                annotationStart = nil
                currentAnnotation = nil
                pencilPoints.removeAll()
                return
            }
            guard purpose == .stillImage else { return }
            guard selectionRect.contains(point) else { return }
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
            if tool == .pencil {
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
            selectionOptionsBar.isHidden = true
            updateToolButtons()
            needsLayout = true
        case .editing:
            if activeResize != nil {
                activeResize = nil
                needsLayout = true
                needsDisplay = true
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

    override func keyDown(with event: NSEvent) {
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
        addToolButton(.number, symbol: "number.circle", help: "序号")
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
        let control = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: self, action: #selector(toolbarAction(_:)))
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
            tool = selectedTool
            updateToolButtons()
            return
        }
        switch sender.tag {
        case 10: document.undo(); needsDisplay = true
        case 11: document.redo(); needsDisplay = true
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
            button.contentTintColor = candidate == tool ? .systemCyan : .labelColor
        }
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
            return .rectangle(SelectionRect(start: start, end: end).rect, accent, 3)
        case .arrow:
            return .arrow(from: start, to: end, accent, 3)
        case .pencil:
            return .pencil(pencilPoints.isEmpty ? [start, end] : pencilPoints, accent, 3)
        case .number:
            return .number(
                center: numberCenter(for: end),
                value: document.nextSequenceNumber,
                color: accent,
                diameter: 28
            )
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

    private func setStroke(_ color: RGBAColor, width: CGFloat) {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setStroke()
        NSBezierPath.defaultLineWidth = width
        NSBezierPath.defaultLineCapStyle = .round
        NSBezierPath.defaultLineJoinStyle = .round
    }

    private func finish(_ action: CaptureResultAction) {
        if case .recordGIF = action {
            onResult(screenshot, selectionRect, action)
            return
        }
        if case .scrollCapture = action {
            onResult(screenshot, selectionRect, action)
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
        guard let result = AnnotationRenderer.render(baseImage: crop, annotations: mapped) else {
            NSSound.beep()
            return
        }
        onResult(result, selectionRect, action)
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
