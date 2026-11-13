import AppKit
import SwiftUI

/// 用原生按钮保留首击、键盘和辅助功能行为；命中范围来自实际 AppKit 布局。
struct ShelfActions: NSViewRepresentable {
    @ObservedObject var coordinator: ShelfCoordinator

    func makeNSView(context: Context) -> ShelfActionsView {
        let view = ShelfActionsView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShelfActionsView, context: Context) { configure(view) }

    private func configure(_ view: ShelfActionsView) {
        view.configure(hasItems: !coordinator.items.isEmpty, isDragging: coordinator.isDragging,
                       canUndo: coordinator.canUndoRemoval)
        view.onClear = { coordinator.clearAll() }
        view.onUndo = { coordinator.undoLastRemoval() }
        view.onCapture = { coordinator.onCaptureRequested?() }
        coordinator.controlsHitTest = { [weak view] point in view?.containsPanelPoint(point) ?? false }
    }
}

@MainActor
final class ShelfActionsView: NSView {
    let primaryButton = ShelfActionButton()
    let undoButton = ShelfActionButton()
    var onClear: () -> Void = {}
    var onUndo: () -> Void = {}
    var onCapture: () -> Void = {}
    private var hasItems = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for button in [primaryButton, undoButton] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .center
            button.target = self
            addSubview(button)
        }
        primaryButton.action = #selector(primaryAction)
        undoButton.action = #selector(undoAction)
        undoButton.title = "撤销取下"
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        undoButton.toolTip = "仅恢复刚才取下的卡片，并保留原来的顺序"
        undoButton.setAccessibilityLabel("撤销刚才取下的卡片")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(hasItems: Bool, isDragging: Bool, canUndo: Bool) {
        self.hasItems = hasItems
        primaryButton.title = hasItems ? "一键清理" : "开始截图"
        primaryButton.image = NSImage(systemSymbolName: hasItems ? "tray.and.arrow.down" : "viewfinder",
                                      accessibilityDescription: nil)
        primaryButton.toolTip = hasItems ? "取下全部卡片，原文件保留；可立即撤销" : "开始选择截图区域"
        primaryButton.setAccessibilityLabel(primaryButton.title)
        primaryButton.isEnabled = !isDragging
        undoButton.isHidden = !canUndo
        undoButton.isEnabled = !isDragging
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttons = [primaryButton, undoButton].filter { !$0.isHidden }
        let widths = buttons.map { max(88, $0.intrinsicContentSize.width) }
        let gap: CGFloat = 4
        let total = widths.reduce(0, +) + CGFloat(max(0, buttons.count - 1)) * gap
        var x = (bounds.width - total) / 2
        for (button, width) in zip(buttons, widths) {
            button.frame = NSRect(x: x, y: (bounds.height - 30) / 2, width: width, height: 30)
            x += width + gap
        }
    }

    func containsPanelPoint(_ point: CGPoint) -> Bool {
        guard let root = window?.contentView, root.bounds.contains(point),
              !isHiddenOrHasHiddenAncestor else { return false }
        let local = convert(point, from: root)
        return [primaryButton, undoButton].contains { !$0.isHidden && $0.frame.contains(local) }
    }

    @objc private func primaryAction() { hasItems ? onClear() : onCapture() }
    @objc private func undoAction() { onUndo() }
}

final class ShelfActionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
