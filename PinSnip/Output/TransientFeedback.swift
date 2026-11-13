import AppKit

@MainActor
enum TransientFeedback {
    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?

    static func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }

    static func show(message: String) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        dismiss()

        let visibleFrame = screen.visibleFrame
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = min(400, visibleFrame.width - 56)
        let size = label.fittingSize
        let width = size.width + 28
        let height = size.height + 20
        let frame = NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + 24,
                           width: width, height: height)
        let feedback = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        feedback.isReleasedWhenClosed = false
        feedback.isOpaque = false
        feedback.backgroundColor = .clear
        feedback.hasShadow = true
        feedback.hidesOnDeactivate = false
        feedback.ignoresMouseEvents = true
        feedback.level = .floating
        feedback.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 14, y: 10, width: size.width, height: size.height)
        background.addSubview(label)
        feedback.contentView = background
        panel = feedback
        feedback.orderFrontRegardless()
        NSAccessibility.post(element: feedback, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        dismissal = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            feedback.orderOut(nil)
            panel = nil
            dismissal = nil
        }
    }
}
