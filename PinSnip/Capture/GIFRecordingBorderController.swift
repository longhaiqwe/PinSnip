import AppKit
import PinSnipCore

@MainActor
final class GIFRecordingBorderController: NSWindowController {
    init(screen: NSScreen, selectionRect: CGRect) {
        let lineWidth: CGFloat = 3
        let layout = GIFRecordingBorderLayout(
            screenFrame: screen.frame,
            selectionRect: selectionRect,
            lineWidth: lineWidth
        )
        let panel = NSPanel(
            contentRect: layout.windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.contentView = GIFRecordingBorderView(
            frame: CGRect(origin: .zero, size: layout.windowFrame.size),
            borderRect: layout.borderRect,
            lineWidth: lineWidth
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        window?.orderFrontRegardless()
    }

    func dismiss() {
        close()
    }
}

private final class GIFRecordingBorderView: NSView {
    private let borderRect: CGRect
    private let lineWidth: CGFloat

    init(frame: CGRect, borderRect: CGRect, lineWidth: CGFloat) {
        self.borderRect = borderRect
        self.lineWidth = lineWidth
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let borderColor = GIFRecordingPanelLayout.recordingBorderColor
        NSColor(
            srgbRed: borderColor.red,
            green: borderColor.green,
            blue: borderColor.blue,
            alpha: borderColor.alpha
        ).setStroke()
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = lineWidth
        path.stroke()
    }
}
