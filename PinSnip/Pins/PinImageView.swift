import AppKit
import PinSnipCore

@MainActor
final class PinImageView: NSView {
    let image: CGImage
    var transformState = PinTransform() {
        didSet { needsDisplay = true }
    }
    var onScroll: ((CGFloat, Bool) -> Void)?
    var onKeyAction: ((Character, NSEvent.ModifierFlags) -> Void)?

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        if transformState.isFlippedHorizontally {
            context.scaleBy(x: -1, y: 1)
        }
        if transformState.isFlippedVertically {
            context.scaleBy(x: 1, y: -1)
        }
        context.rotate(by: CGFloat(transformState.rotationQuarterTurns) * .pi / 2)

        let width: CGFloat
        let height: CGFloat
        if transformState.rotationQuarterTurns.isMultiple(of: 2) {
            width = bounds.width
            height = bounds.height
        } else {
            width = bounds.height
            height = bounds.width
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.orderOut(nil)
            return
        }
        window?.makeKey()
        window?.makeFirstResponder(self)
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY, event.modifierFlags.contains(.control))
    }

    override func keyDown(with event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else {
            super.keyDown(with: event)
            return
        }
        onKeyAction?(character, event.modifierFlags)
    }
}
