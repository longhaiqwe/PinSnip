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
    @Published private(set) var canUndoRemoval = false
    var onCaptureRequested: (() -> Void)?
    private var lastRemoval: (order: [UUID], items: [UUID: ShelfStorage.ArchivedItem])?

    @Published private(set) var dropIndicator: CGPoint?
    private(set) var draggedItemID: UUID?
    var slotRects: [UUID: CGRect] = [:]

    var hitRects: [UUID: CGRect] = [:]
    var controlsHitTest: ((CGPoint) -> Bool)?
    @Published var viewportRect: CGRect = .zero
    @Published private(set) var visibleItemIDs: Set<UUID> = []

    private var panel: ShelfPanel?
    private var mouseTimer: Timer?
    private var hotZoneSince: Date?
    private var awaySince: Date?
    private var peekUntil: Date = .distantPast
    private var menuBarSuppressed: Bool = false
    private var clickMonitors: [Any] = []
    private var keyboardInteractionActive = false

    weak var pinManager: PinWindowManager?

    private static let revealDelay: TimeInterval = 0.25
    private static let retractDelay: TimeInterval = 0.50

    private let storage: ShelfStorage
    private let storageErrorHandler: ((Error) -> Void)?

    init(
        edgeStore: ShelfEdgeStore = ShelfEdgeStore(),
        storage: ShelfStorage = ShelfStorage(),
        storageErrorHandler: ((Error) -> Void)? = nil
    ) {
        self.edgeStore = edgeStore
        self.storage = storage
        self.storageErrorHandler = storageErrorHandler
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
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3)
    }

    /// 启动晾衣架系统
    func start(pinManager: PinWindowManager) {
        self.pinManager = pinManager
        restoreStoredItems()
        let rootView = ShelfView(coordinator: self)
        let hostView = ShelfHostingView(rootView: rootView)
        hostView.sizingOptions = []
        hostView.registerForDraggedTypes([ShelfGrabView.shelfItemType])

        let shelfPanel = ShelfPanel(content: hostView)
        shelfPanel.placeOnScreen(edge: edge)
        shelfPanel.orderFrontRegardless()
        panel = shelfPanel

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

    func toggleForKeyboardInteraction() {
        if isRevealed, panel?.isKeyWindow == true { setRevealed(false); panel?.resignKey() }
        else { showForKeyboardInteraction() }
    }

    func showForKeyboardInteraction() {
        panel?.placeOnScreen(edge: edge)
        setRevealed(true)
        keyboardInteractionActive = true
        panel?.makeKeyAndOrderFront(nil)
        panel?.selectNextKeyView(nil)
    }

    func updateVisibleItems() {
        let visible = Set(slotRects.compactMap { id, frame in
            frame.intersects(viewportRect) ? id : nil
        })
        if visibleItemIDs != visible { visibleItemIDs = visible }
    }

    func setRevealed(_ revealed: Bool) {
        guard isRevealed != revealed else { return }
        visibility.setRevealed(revealed)
        if !revealed {
            keyboardInteractionActive = false
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
        persistOrder()
        clearDropIndicator()
        return true
    }

    /// 将新截取的图像挂在晾衣架上
    @discardableResult
    func hang(image: CGImage, fromScreenRect: CGRect? = nil, reportError: Bool = true) -> Bool {
        do {
            append(try storage.storeImage(image))
            return true
        } catch {
            if reportError { showStorageError(error) }
            return false
        }
    }

    @discardableResult
    func hangGIF(_ data: Data, reportError: Bool = true) -> Bool {
        do {
            try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
            append(try ShelfItem.storeGIF(data, in: storage.directory))
            return true
        } catch {
            if reportError { showStorageError(error) }
            return false
        }
    }

    private func append(_ item: ShelfItem) {
        items.insert(item, at: 0)

        persistOrder()

        // 新截图挂上时，让面板在鼠标所在屏幕展开，并短暂停留让用户感知
        panel?.placeOnScreen(edge: edge)
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3.0)
    }

    /// 复制卡片到剪贴板
    func copy(item: ShelfItem) {
        if item.isAnimated {
            do {
                let data = try Data(contentsOf: item.url)
                CaptureOutputService.copyGIF(data) { [weak self] succeeded in
                    if succeeded { self?.showCopiedFeedback(for: item.id) }
                }
            } catch {
                showStorageError(error)
            }
        } else if item.copy(to: .general) {
            showCopiedFeedback(for: item.id)
        } else {
            showStorageError(CocoaError(.fileReadUnknown))
        }
    }

    private func showCopiedFeedback(for id: UUID) {
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedID == id {
                self?.copiedID = nil
            }
        }
    }

    /// 将卡片取下并转为桌面贴图 (PinWindow)
    func pinToDesktop(item: ShelfItem) {
        guard let pinManager else { return }
        do {
            let data = try Data(contentsOf: item.url)
            if item.isAnimated {
                guard let animation = AnimatedImage(data: data) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                pinManager.pin(animation)
            } else {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                pinManager.pin(cgImage)
            }
            discard(item: item)
        } catch {
            showStorageError(error)
        }
    }

    /// 从晾衣架取下，原文件归档以便恢复。
    func discard(item: ShelfItem) {
        do {
            let order = items.map(\.id)
            let archived = try storage.archive(item)
            if let archived { rememberRemoval(order: order, items: [item.id: archived]) }
            items.removeAll { $0.id == item.id }
            persistOrder()
        } catch {
            // 取下动画先隐藏卡片；归档失败时恢复显示和命中区域，允许重试。
            item.isFalling = false
            showStorageError(error)
        }
    }

    /// 一次取下全部卡片，保留原文件，失败项继续留在架上。
    func clearAll() {
        guard !items.isEmpty, !isDragging else { return }
        let order = items.map(\.id)
        let result = storage.archiveAll(items)
        if !result.archivedItems.isEmpty { rememberRemoval(order: order, items: result.archivedItems) }
        items.removeAll { result.archivedIDs.contains($0.id) }
        copiedID = nil
        slotRects = slotRects.filter { !result.archivedIDs.contains($0.key) }
        hitRects = hitRects.filter { !result.archivedIDs.contains($0.key) }
        clearDropIndicator()
        persistOrder()
        peekUntil = Date().addingTimeInterval(3)
        if let error = result.firstError { showStorageError(error) }
    }

    private func rememberRemoval(order: [UUID], items: [UUID: ShelfStorage.ArchivedItem]) {
        lastRemoval = (order, items)
        canUndoRemoval = true
    }

    func undoLastRemoval() {
        guard let removal = lastRemoval, !isDragging else { return }
        var restored: [UUID: ShelfItem] = [:]
        var failed: [UUID: ShelfStorage.ArchivedItem] = [:]
        var firstError: Error?
        for (id, archived) in removal.items {
            do { restored[id] = try storage.restoreArchivedItem(archived) }
            catch { failed[id] = archived; if firstError == nil { firstError = error } }
        }
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let priorIDs = Set(removal.order)
        // 本次清理之后的新截图继续排在前面，恢复项沿用清理前的相对顺序。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            items = items.filter { !priorIDs.contains($0.id) } + removal.order.compactMap { restored[$0] ?? existing[$0] }
        }
        lastRemoval = failed.isEmpty ? nil : (removal.order, failed)
        canUndoRemoval = !failed.isEmpty
        persistOrder()
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3)
        if let firstError { showStorageError(firstError) }
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
                ShelfLayout.containsPointer(mouse, in: Self.menuBarBand(of: $0))
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

        let screenUnderPointer = ShelfPanel.screen(containing: mouse)
        let inMenuBar = screenUnderPointer.map {
            ShelfLayout.containsPointer(mouse, in: Self.menuBarBand(of: $0))
        } ?? false

        if !inMenuBar {
            menuBarSuppressed = false
        }

        let inHotZone = screenUnderPointer.map { screen in
            let zone = ShelfLayout.activationZone(
                in: screen.frame, edge: edge, topInset: Self.menuBarBand(of: screen).height,
                visibleFrame: screen.visibleFrame
            )
            return ShelfLayout.containsPointer(mouse, in: zone)
        } ?? false

        // 未展开状态：在所选边缘停留 0.25 秒展开
        guard isRevealed else {
            if let screen = screenUnderPointer, inHotZone, !menuBarSuppressed {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    panel.placeOnScreen(screen, edge: edge)
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
        let inside = ShelfLayout.containsPointer(mouse, in: zone)

        let isBusy = isDragging || now < peekUntil || visibility.isHeldForCapture
            || (keyboardInteractionActive && panel.isKeyWindow)
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

    /// 卡片和操作按钮接收鼠标，其余空白区域穿透给底层应用。
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard let panel else { return }
        updateMousePassThrough(mouse, in: panel)
    }

    func updateMousePassThrough(_ mouse: NSPoint, in panel: ShelfPanel) {
        guard !isDragging, let content = panel.contentView else { return }
        // 只通过 AppKit 转换一次，兼容窗口原点和内容视图的坐标方向。
        let local = content.convert(panel.convertPoint(fromScreen: mouse), from: nil)
        let overCard = hitRects.values.contains {
            $0.insetBy(dx: -4, dy: -4).contains(local)
        }
        let interactive = isRevealed && (overCard || (controlsHitTest?(local) ?? false))
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }

    private func restoreStoredItems() {
        do {
            items = try storage.loadItems()
            persistOrder()
        } catch {
            showStorageError(error)
        }
    }

    private func persistOrder() {
        do { try storage.saveOrder(items) }
        catch { showStorageError(error) }
    }

    func restoreArchivedItems() {
        do { try storage.restoreArchived() }
        catch { showStorageError(error) }
        restoreStoredItems()
        lastRemoval = nil
        canUndoRemoval = false
        setRevealed(true)
        peekUntil = Date().addingTimeInterval(3)
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(storage.directory)
    }

    private func showStorageError(_ error: Error) {
        if let storageErrorHandler {
            storageErrorHandler(error)
            return
        }
        let alert = NSAlert(error: error)
        alert.messageText = "无法读写本地截图"
        alert.runModal()
    }
}
