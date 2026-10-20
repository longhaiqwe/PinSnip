import AppKit
import Foundation
import PinSnipCore
import SwiftUI

/// 桌面晾衣架核心控制器：负责面板生命周期、鼠标悬浮/收起跟踪、截图挂载与交互桥接
@MainActor
final class ShelfCoordinator: ObservableObject {
    static let shared = ShelfCoordinator()

    @Published private(set) var edge: ShelfEdge
    private let edgeStore: ShelfEdgeStore

    @Published var items: [ShelfItem] = []
    @Published private var visibility = ShelfVisibilityState()
    var isRevealed: Bool { visibility.isRevealed }
    @Published var copiedID: UUID?
    @Published var isDragging: Bool = false

    @Published private(set) var dropIndicator: CGPoint?
    private(set) var draggedItemID: UUID?
    var slotRects: [UUID: CGRect] = [:]

    var hitRects: [UUID: CGRect] = [:]

    private var panel: ShelfPanel?
    private var mouseTimer: Timer?
    private var hotZoneSince: Date?
    private var awaySince: Date?
    private var peekUntil: Date = .distantPast
    private var menuBarSuppressed: Bool = false
    private var clickMonitors: [Any] = []
    private var maxCapacity: Int = 10

    weak var pinManager: PinWindowManager?

    private static let revealDelay: TimeInterval = 0.25
    private static let retractDelay: TimeInterval = 0.50

    private let storageFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("PinSnip/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init(edgeStore: ShelfEdgeStore = ShelfEdgeStore()) {
        self.edgeStore = edgeStore
        edge = edgeStore.load()
    }

    func setEdge(_ newEdge: ShelfEdge) {
        guard edge != newEdge else { return }
        edge = newEdge
        edgeStore.save(newEdge)
        hotZoneSince = nil
        awaySince = nil
        menuBarSuppressed = false
        slotRects = [:]
        clearDropIndicator()
        hitRects = [:]
        panel?.ignoresMouseEvents = true
        panel?.placeOnScreen(edge: edge)
        updateCapacity()
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3)
    }

    /// 启动晾衣架系统
    func start(pinManager: PinWindowManager) {
        self.pinManager = pinManager
        let rootView = ShelfView(coordinator: self)
        let hostView = ShelfHostingView(rootView: rootView)
        hostView.sizingOptions = []
        hostView.registerForDraggedTypes([ShelfGrabView.shelfItemType])

        let shelfPanel = ShelfPanel(content: hostView)
        shelfPanel.placeOnScreen(edge: edge)
        shelfPanel.orderFrontRegardless()
        panel = shelfPanel

        updateCapacity()
        startMouseTracking()
        watchMenuBarClicks()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screenParametersChanged() {
        panel?.placeOnScreen(panel?.screen, edge: edge)
        slotRects = [:]
        clearDropIndicator()
        hitRects = [:]
        updateCapacity()
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        stopMouseTracking()
        for monitor in clickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors.removeAll()
        panel?.close()
        panel = nil
    }

    /// 切换展开/收起
    func toggle() {
        if isRevealed {
            setRevealed(false)
        } else {
            panel?.placeOnScreen(edge: edge)
            updateCapacity()
            setRevealed(true)
        }
    }

    func setRevealed(_ revealed: Bool) {
        guard isRevealed != revealed else { return }
        visibility.setRevealed(revealed)
        if !revealed {
            panel?.ignoresMouseEvents = true
        }
    }

    func setCaptureActive(_ active: Bool) {
        if active { visibility.beginCapture() }
        else { visibility.endCapture() }
        hotZoneSince = nil
        awaySince = nil
    }

    private func automaticallyHide() {
        visibility.automaticallyHide()
        if !isRevealed { panel?.ignoresMouseEvents = true }
    }

    func beginDragging(item: ShelfItem) {
        draggedItemID = item.id
        isDragging = true
        // 空白间隙也必须接收架内放置，否则只能落在另一张图片上。
        panel?.ignoresMouseEvents = false
    }

    func endDragging() {
        draggedItemID = nil
        isDragging = false
        clearDropIndicator()
        awaySince = nil
        panel?.ignoresMouseEvents = true
    }

    func clearDropIndicator() { dropIndicator = nil }

    @discardableResult
    func updateDrop(at point: CGPoint) -> Int? {
        guard let id = draggedItemID,
              let index = ShelfReordering.insertionIndex(
                draggedID: id, orderedIDs: items.map(\.id), frames: slotRects, point: point, edge: edge
              ) else {
            clearDropIndicator()
            return nil
        }
        let remaining = items.filter { $0.id != id }.compactMap { slotRects[$0.id] }
        let coordinate: CGFloat
        if remaining.isEmpty {
            let frame = slotRects[id]!
            coordinate = edge.isVertical ? frame.midY : frame.midX
        } else if index == 0 {
            coordinate = (edge.isVertical ? remaining[0].minY : remaining[0].minX) - 8
        } else if index == remaining.count {
            coordinate = (edge.isVertical ? remaining[index - 1].maxY : remaining[index - 1].maxX) + 8
        } else {
            let before = remaining[index - 1]
            let after = remaining[index]
            coordinate = edge.isVertical ? (before.maxY + after.minY) / 2 : (before.maxX + after.minX) / 2
        }
        let indicator = edge.isVertical
            ? CGPoint(x: ShelfLayout.panelHeight / 2, y: coordinate)
            : CGPoint(x: coordinate, y: ShelfLayout.panelHeight / 2)
        if dropIndicator != indicator { dropIndicator = indicator }
        return index
    }

    func acceptDrop(at point: CGPoint) -> Bool {
        guard let id = draggedItemID, let index = updateDrop(at: point) else { return false }
        let ids = ShelfReordering.moving(id, to: index, in: items.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = ids.compactMap { byID[$0] }
        clearDropIndicator()
        return true
    }

    /// 将新截取的图像挂在晾衣架上
    func hang(image: CGImage, fromScreenRect: CGRect? = nil) {
        let id = UUID()
        let filename = "screenshot-\(id.uuidString).png"
        let fileURL = storageFolder.appendingPathComponent(filename)

        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }
        try? pngData.write(to: fileURL)

        let originalSize = CGSize(width: image.width, height: image.height)
        let thumbSize = ShelfLayout.photoSize(for: originalSize)
        let thumbImage = NSImage(cgImage: image, size: thumbSize)

        let item = ShelfItem(
            id: id,
            url: fileURL,
            thumb: thumbImage,
            originalSize: originalSize
        )

        append(item)
    }

    func hangGIF(_ data: Data) {
        do {
            append(try ShelfItem.storeGIF(data, in: storageFolder))
        } catch {
            NSSound.beep()
        }
    }

    private func append(_ item: ShelfItem) {
        items.insert(item, at: 0)

        // 超过容量移除最旧卡片
        if items.count > maxCapacity {
            let overflow = items.suffix(from: maxCapacity)
            for oldItem in overflow {
                try? FileManager.default.removeItem(at: oldItem.url)
            }
            items.removeLast(items.count - maxCapacity)
        }

        // 新截图挂上时，让面板在鼠标所在屏幕展开，并短暂停留让用户感知
        panel?.placeOnScreen(edge: edge)
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3.0)
    }

    /// 复制卡片到剪贴板
    func copy(item: ShelfItem) {
        guard item.copy(to: .general) else { return }

        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedID == item.id {
                self?.copiedID = nil
            }
        }
    }

    /// 将卡片取下并转为桌面贴图 (PinWindow)
    func pinToDesktop(item: ShelfItem) {
        if item.isAnimated {
            guard let animation = item.loadAnimation(), let pinManager else { return }
            pinManager.pin(animation)
            discard(item: item)
            return
        }
        guard let data = try? Data(contentsOf: item.url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }

        pinManager?.pin(cgImage)
        discard(item: item)
    }

    /// 丢弃并从晾衣架取下
    func discard(item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url)
    }

    /// 打开系统标注 (Markup)
    func openMarkup(item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    /// 在访达中定位
    func revealInFinder(item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - 鼠标触边检测与智能避让

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel?.ignoresMouseEvents = true
    }

    private static func menuBarBand(of screen: NSScreen) -> NSRect {
        var h = screen.frame.maxY - screen.visibleFrame.maxY
        if h < 1 {
            h = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        }
        return NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - h,
            width: screen.frame.width,
            height: h
        )
    }

    private func watchMenuBarClicks() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            guard let self, self.edge == .top else { return }
            let mouse = NSEvent.mouseLocation
            let inAnyMenuBar = NSScreen.screens.contains {
                NSMouseInRect(mouse, Self.menuBarBand(of: $0), false)
            }
            if inAnyMenuBar {
                self.menuBarSuppressed = true
                self.hotZoneSince = nil
                if self.isRevealed {
                    self.automaticallyHide()
                }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: handler
        ) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { e in handler(e); return e }
        ) {
            clickMonitors.append(local)
        }
    }

    private func tick() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let now = Date()

        let screenUnderPointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inMenuBar = screenUnderPointer.map {
            NSMouseInRect(mouse, Self.menuBarBand(of: $0), false)
        } ?? false

        if !inMenuBar {
            menuBarSuppressed = false
        }

        let inHotZone = screenUnderPointer.map { screen in
            ShelfLayout.activationZone(
                in: screen.frame, edge: edge, topInset: Self.menuBarBand(of: screen).height
            ).contains(mouse)
        } ?? false

        // 未展开状态：在所选边缘停留 0.25 秒展开
        guard isRevealed else {
            if let screen = screenUnderPointer, inHotZone, !menuBarSuppressed {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    panel.placeOnScreen(screen, edge: edge)
                    updateCapacity()
                    setRevealed(true)
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        updateMousePassThrough(mouse)

        // 已展开状态：检测光标是否离开
        var zone = panel.frame
        if let screen = panel.screen {
            zone = ShelfLayout.retentionZone(panel: panel.frame, screen: screen.frame, edge: edge)
        }
        let inside = NSMouseInRect(mouse, zone, false)

        let isBusy = isDragging || now < peekUntil || visibility.isHeldForCapture
        if inside || isBusy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                automaticallyHide()
            }
        }
    }

    /// 关键：动态判断光标是否在卡片上，仅在卡片上时接收鼠标，其余区域事件穿透给底层应用
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard let panel, !isDragging else { return }
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        let overCard = hitRects.values.contains {
            $0.insetBy(dx: -4, dy: -4).contains(flipped)
        }
        if panel.ignoresMouseEvents == overCard {
            panel.ignoresMouseEvents = !overCard
        }
    }

    private func updateCapacity() {
        guard let panel else { return }
        // 切换方向不改变队列容量，较长的队列通过滚动浏览。
        maxCapacity = ShelfLayout.capacity(forWidth: panel.screen?.visibleFrame.width ?? panel.frame.width)
    }
}
