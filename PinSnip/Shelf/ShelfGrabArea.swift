import AppKit
import SwiftUI

/// 桥接 AppKit 拖拽协议与手势，支持把卡片直接拖到任意 App 或访达，支持单击复制与双击贴图
struct ShelfGrabArea: NSViewRepresentable {
    let item: ShelfItem
    let onCopy: () -> Void
    let onPin: () -> Void
    let onMarkup: () -> Void
    let onDiscard: () -> Void
    let onRevealInFinder: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> ShelfGrabView {
        let view = ShelfGrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShelfGrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ShelfGrabView) {
        view.toolTip = item.isAnimated
            ? "单击复制动图 · 双击贴图播放 · 长按打开 · 架内拖动排序 · 拖出导出 GIF · 左上角取下"
            : "单击复制 · 双击贴图 · 长按标注 · 架内拖动排序 · 拖出导出 · 左上角取下"
        view.setAccessibilityLabel(item.isAnimated ? "GIF 动图缩略图" : "截图缩略图")
        view.setAccessibilityHelp(view.toolTip)
        view.itemID = item.id
        view.url = item.url
        view.dragImage = item.thumb
        view.onClick = onCopy
        view.onDoubleClick = onPin
        view.onLongPress = onMarkup
        view.onDiscard = onDiscard
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        view.menuProvider = {
            let menu = NSMenu()
            menu.addItem(ShelfMenuItem(item.isAnimated ? "复制动图" : "复制图片") { onCopy() })
            menu.addItem(ShelfMenuItem("贴在桌面 (Pin)") { onPin() })
            menu.addItem(ShelfMenuItem(item.isAnimated ? "打开动图" : "标注 (Markup)") { onMarkup() })
            menu.addItem(ShelfMenuItem("在访达中显示") { onRevealInFinder() })
            menu.addItem(.separator())
            menu.addItem(ShelfMenuItem("从晾衣架取下") { onDiscard() })
            return menu
        }
    }
}

final class ShelfGrabView: NSView, NSDraggingSource {
    static var isDragging = false
    static let shelfItemType = NSPasteboard.PasteboardType("com.longhai.pinsnip.shelf-item")

    var itemID: UUID?
    var didDropOnShelf = false

    var url: URL?
    var dragImage: NSImage?
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var menuProvider: () -> NSMenu = { NSMenu() }

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false

    private static let holdDuration: TimeInterval = 0.45
    private static let crossHitSize: CGFloat = 26

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isInCross(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let corner = NSRect(
            x: 0,
            y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
            width: Self.crossHitSize,
            height: Self.crossHitSize
        )
        return corner.contains(p)
    }

    override func mouseDown(with event: NSEvent) {
        if isInCross(event) {
            downPoint = nil
            onDiscard()
            return
        }
        if event.clickCount == 2 {
            downPoint = nil
            endPress()
            onDoubleClick()
            return
        }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onLongPress()
            }
        }
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag, let url else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }
        startedDrag = true
        endPress()

        let writer = NSPasteboardItem()
        writer.setString(url.absoluteString, forType: .fileURL)
        if let itemID { writer.setString(itemID.uuidString, forType: Self.shelfItemType) }
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(imageFrame(), contents: dragImage)
        didDropOnShelf = false
        ShelfGrabView.isDragging = true
        onDragStart()
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        endPress()
        if downPoint != nil && !startedDrag && !didLongPress && event.clickCount == 1 {
            onClick()
        }
        downPoint = nil
        didLongPress = false
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .delete] : .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) -> Void {
        ShelfGrabView.isDragging = false
        startedDrag = false
        downPoint = nil

        // 架内的 move 只调整顺序，不能走文件搬走后的删除逻辑。
        if didDropOnShelf {
            didDropOnShelf = false
            onDragEnd()
            return
        }

        if operation.contains(.delete) {
            onDragEnd()
            onDiscard()
            return
        }

        onDragEnd()
        // 拖入访达文件夹 (move) 时，文件已被移至新目录，稍后将其从晾衣架取下
        if operation.contains(.move) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onDiscard()
            }
        }
    }

    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ShelfMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
