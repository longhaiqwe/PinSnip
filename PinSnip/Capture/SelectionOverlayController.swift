import AppKit
import PinSnipCore

@MainActor
final class SelectionOverlayController: NSWindowController {
    init(
        screen: NSScreen,
        screenshot: CGImage,
        windowCandidates: [WindowCandidate],
        initialPointer: CGPoint,
        initialSelectionRect: CGRect,
        purpose: CaptureOverlayPurpose,
        onResult: @escaping (CaptureResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let styleMask: NSWindow.StyleMask = CaptureOverlayPresentationPolicy.preservesFrontmostApplication
            ? [.borderless, .nonactivatingPanel]
            : [.borderless]
        let panel = CapturePanel(
            contentRect: screen.frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        let overlay = SelectionOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenshot: screenshot,
            windowCandidates: windowCandidates,
            initialPointer: initialPointer,
            initialSelectionRect: initialSelectionRect,
            purpose: purpose,
            onResult: onResult,
            onCancel: onCancel
        )
        panel.contentView = overlay
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.animationBehavior = CaptureOverlayPresentationPolicy.animatesPresentation
            ? .default
            : .none
        panel.hidesOnDeactivate = CaptureOverlayPresentationPolicy.hidesOnDeactivate
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        if CaptureOverlayPresentationPolicy.preservesFrontmostApplication {
            window?.orderFrontRegardless()
            window?.makeKey()
        } else {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        if let view = window?.contentView {
            window?.makeFirstResponder(view)
        }
    }

    func addWindowCandidates(_ candidates: [WindowCandidate]) {
        (window?.contentView as? SelectionOverlayView)?
            .addWindowCandidates(candidates)
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool {
        !CaptureOverlayPresentationPolicy.preservesFrontmostApplication
    }
}
