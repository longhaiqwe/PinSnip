import AppKit
import PinSnipCore
import SwiftUI

/// 悬挂在屏幕边缘的无边框透明悬浮面板
final class ShelfPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 获取光标当前所在的屏幕
    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// 将面板对齐到所选屏幕边缘的可见区域
    func placeOnScreen(_ screen: NSScreen? = nil, edge: ShelfEdge) {
        guard let targetScreen = screen ?? ShelfPanel.screenUnderPointer() else { return }
        let target = ShelfLayout.panelFrame(in: targetScreen.visibleFrame, edge: edge)
        if frame != target {
            setFrame(target, display: true)
        }
    }
}

/// 系统文件拖拽的架内落点；仅接受本次从晾衣架发起的拖动。
final class ShelfHostingView: NSHostingView<ShelfView> {
    private var coordinator: ShelfCoordinator { rootView.coordinator }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? ShelfGrabView,
              let id = coordinator.draggedItemID else { return false }
        return source.itemID == id
            && sender.draggingPasteboard.string(forType: ShelfGrabView.shelfItemType) == id.uuidString
    }

    private func point(_ sender: NSDraggingInfo) -> CGPoint {
        let local = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender), coordinator.updateDrop(at: point(sender)) != nil else { return [] }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        scrollNearEdge(at: point(sender))
        return coordinator.updateDrop(at: point(sender)) == nil ? [] : .move
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator.clearDropIndicator()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender), coordinator.acceptDrop(at: point(sender)) else { return false }
        (sender.draggingSource as? ShelfGrabView)?.didDropOnShelf = true
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        coordinator.clearDropIndicator()
    }

    private func scrollNearEdge(at point: CGPoint) {
        func findScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll(in: $0) }.first
        }
        guard let scroll = findScroll(in: self), let document = scroll.documentView else { return }
        let vertical = coordinator.edge.isVertical
        let coordinate = vertical ? point.y : point.x
        let length = vertical ? bounds.height : bounds.width
        let delta: CGFloat = coordinate < 36 ? -12 : (coordinate > length - 36 ? 12 : 0)
        guard delta != 0 else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        if vertical {
            origin.y = min(max(0, origin.y + (document.isFlipped ? delta : -delta)), max(0, document.bounds.height - clip.bounds.height))
        } else {
            origin.x = min(max(0, origin.x + delta), max(0, document.bounds.width - clip.bounds.width))
        }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }
}
