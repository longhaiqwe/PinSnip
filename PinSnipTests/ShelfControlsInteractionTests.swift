import AppKit
import PinSnipCore
import SwiftUI
import XCTest

@MainActor
final class ShelfControlsInteractionTests: XCTestCase {
    func testClearAndUndoReceiveClicksInEveryDockPosition() async throws {
        _ = NSApplication.shared
        for edge in ShelfEdge.allCases {
            let fixture = try Fixture(edge: edge)
            defer { fixture.cleanup() }
            let first = try fixture.storage.storeImage(image())
            let second = try fixture.storage.storeImage(image())
            fixture.coordinator.items = [second, first]
            fixture.coordinator.setRevealed(true)
            let host = ShelfHostingView(rootView: ShelfView(coordinator: fixture.coordinator))
            host.sizingOptions = []
            let panel = ShelfPanel(content: host)
            panel.setFrame(CGRect(x: 130, y: 90, width: edge.isVertical ? 210 : 720,
                                  height: edge.isVertical ? 600 : 210), display: true)
            defer { panel.close() }
            try await waitUntil { !self.descendants(host).compactMap { $0 as? ShelfActionsView }.isEmpty }
            let actions = try XCTUnwrap(descendants(host).compactMap { $0 as? ShelfActionsView }.first)
            try await waitUntil { actions.bounds.width >= panel.frame.width - 1 }

            assertReceivesPointer(actions.primaryButton, in: panel, coordinator: fixture.coordinator)
            actions.primaryButton.performClick(nil)
            XCTAssertTrue(fixture.coordinator.items.isEmpty, "\(edge)：实际按钮应完成清理")
            try await waitUntil { !actions.undoButton.isHidden && actions.undoButton.frame.maxX <= actions.bounds.width }
            assertReceivesPointer(actions.undoButton, in: panel, coordinator: fixture.coordinator)
            actions.undoButton.performClick(nil)
            XCTAssertEqual(fixture.coordinator.items.map(\.id), [second.id, first.id])

            fixture.coordinator.updateMousePassThrough(panel.convertPoint(toScreen: NSPoint(x: 4, y: 4)), in: panel)
            XCTAssertTrue(panel.ignoresMouseEvents, "\(edge)：操作栏以外空白仍应穿透")
            XCTAssertTrue(fixture.errors.isEmpty)
        }
    }

    func testUndoRestoresOnlyLatestBatchInOriginalOrderAndKeepsNewCapturesFirst() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.cleanup() }
        let historical = try fixture.storage.storeImage(image())
        try fixture.storage.archive(historical)
        let first = try fixture.storage.storeImage(image())
        let second = try fixture.storage.storeImage(image())
        fixture.coordinator.items = [second, first]
        fixture.coordinator.clearAll()
        let new = try fixture.storage.storeImage(image())
        fixture.coordinator.items = [new]

        fixture.coordinator.undoLastRemoval()

        XCTAssertEqual(fixture.coordinator.items.map(\.id), [new.id, second.id, first.id])
        XCTAssertTrue(fixture.coordinator.items[1].thumb === second.thumb)
        XCTAssertTrue(fixture.coordinator.items[2].thumb === first.thumb)
        XCTAssertFalse(fixture.coordinator.items[1].animatesOnAppearance)
        XCTAssertFalse(fixture.coordinator.canUndoRemoval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historical.url.path))
        XCTAssertEqual(try fixture.storage.loadItems().map(\.id), [new.id, second.id, first.id])
    }

    func testUndoRefreshesReplacedArchiveAndLeavesCorruptArchiveAvailableForRetry() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.cleanup() }
        let replaced = try fixture.storage.storeImage(image())
        let damaged = try fixture.storage.storeImage(image())
        let originalBytes = try Data(contentsOf: damaged.url)
        let replacement = try fixture.storage.storeImage(image(width: 40, height: 30))
        let replacementBytes = try Data(contentsOf: replacement.url)
        fixture.coordinator.items = [replaced, damaged]
        fixture.coordinator.clearAll()
        let archive = fixture.directory.appendingPathComponent("Archive")
        let replacedURL = archive.appendingPathComponent(replaced.url.lastPathComponent)
        let damagedURL = archive.appendingPathComponent(damaged.url.lastPathComponent)
        try replacementBytes.write(to: replacedURL, options: .atomic)
        try Data("invalid PNG".utf8).write(to: damagedURL, options: .atomic)

        fixture.coordinator.undoLastRemoval()

        XCTAssertEqual(fixture.coordinator.items.map(\.id), [replaced.id])
        XCTAssertEqual(fixture.coordinator.items.first?.originalSize, CGSize(width: 40, height: 30))
        XCTAssertEqual(try Data(contentsOf: replaced.url), replacementBytes)
        XCTAssertEqual(fixture.errors.count, 1)
        XCTAssertTrue(fixture.coordinator.canUndoRemoval)
        XCTAssertTrue(FileManager.default.fileExists(atPath: damagedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: damaged.url.path))

        try originalBytes.write(to: damagedURL, options: .atomic)
        fixture.coordinator.undoLastRemoval()

        XCTAssertEqual(fixture.coordinator.items.map(\.id), [replaced.id, damaged.id])
        XCTAssertFalse(fixture.coordinator.canUndoRemoval)
        XCTAssertEqual(try Data(contentsOf: damaged.url), originalBytes)
    }

    func testTabMovesBetweenRealCardsAndActionBar() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(edge: .top)
        defer { fixture.cleanup() }
        fixture.coordinator.items = [try fixture.storage.storeImage(image()), try fixture.storage.storeImage(image())]
        fixture.coordinator.setRevealed(true)
        let host = ShelfHostingView(rootView: ShelfView(coordinator: fixture.coordinator))
        host.sizingOptions = []
        let panel = ShelfPanel(content: host)
        panel.setFrame(CGRect(x: 0, y: 0, width: 720, height: 210), display: true)
        defer { panel.close() }
        try await waitUntil { self.descendants(host).compactMap { $0 as? ShelfGrabView }.count == 2 }
        let card = try XCTUnwrap(descendants(host).compactMap { $0 as? ShelfGrabView }.first)
        panel.recalculateKeyViewLoop()
        XCTAssertTrue(panel.makeFirstResponder(card))
        let tab = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48))
        card.keyDown(with: tab)
        XCTAssertFalse(panel.firstResponder === card)
        XCTAssertTrue(panel.firstResponder is ShelfGrabView || panel.firstResponder is NSButton)
    }

    func testPartialClearCanUndoOnlySuccessfullyArchivedCards() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.cleanup() }
        let external = try ShelfStorage(directory: fixture.directory.appendingPathComponent("external")).storeImage(image())
        let first = try fixture.storage.storeImage(image())
        let last = try fixture.storage.storeImage(image())
        fixture.coordinator.items = [first, external, last]

        fixture.coordinator.clearAll()
        XCTAssertEqual(fixture.coordinator.items.map(\.id), [external.id])
        fixture.coordinator.undoLastRemoval()

        XCTAssertEqual(fixture.coordinator.items.map(\.id), [first.id, external.id, last.id])
        XCTAssertEqual(fixture.errors.count, 1)
    }

    func testEmptyShelfButtonStartsCaptureAndDraggingDisablesActions() async throws {
        let fixture = try Fixture(edge: .left)
        defer { fixture.cleanup() }
        var captures = 0
        fixture.coordinator.onCaptureRequested = { captures += 1 }
        let actions = ShelfActionsView()
        actions.onCapture = { fixture.coordinator.onCaptureRequested?() }
        actions.configure(hasItems: false, isDragging: false, canUndo: false)
        actions.primaryButton.performClick(nil)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(actions.primaryButton.title, "开始截图")
        actions.configure(hasItems: true, isDragging: true, canUndo: true)
        XCTAssertFalse(actions.primaryButton.isEnabled)
        XCTAssertFalse(actions.undoButton.isEnabled)
    }

    func testOnlyGIFCardsInsideViewportPlayAndScrollingTransfersPlayback() async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(edge: .top)
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: [
            AnimatedImage.Frame(image: image(), duration: 0.1),
            AnimatedImage.Frame(image: image(), duration: 0.1)
        ]))
        fixture.coordinator.items = try (0..<12).map { _ in try ShelfItem.storeGIF(data, in: fixture.directory) }
        fixture.coordinator.setRevealed(true)
        let host = ShelfHostingView(rootView: ShelfView(coordinator: fixture.coordinator))
        host.sizingOptions = []
        let panel = ShelfPanel(content: host)
        panel.setFrame(CGRect(x: 0, y: 0, width: 400, height: 210), display: true)
        defer { panel.close() }
        try await waitUntil { !fixture.coordinator.visibleItemIDs.isEmpty }
        let initiallyVisible = fixture.coordinator.visibleItemIDs
        XCTAssertLessThan(initiallyVisible.count, 12)
        try await waitUntil { self.descendants(host).compactMap { $0 as? ShelfGIFPreviewView }.filter(\.isAnimating).count == initiallyVisible.count }
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        scroll.contentView.scroll(to: NSPoint(x: 900, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await waitUntil { !fixture.coordinator.visibleItemIDs.isEmpty && fixture.coordinator.visibleItemIDs.isDisjoint(with: initiallyVisible) }
        let visibleCount = fixture.coordinator.visibleItemIDs.count
        try await waitUntil { self.descendants(host).compactMap { $0 as? ShelfGIFPreviewView }.filter(\.isAnimating).count == visibleCount }
        fixture.coordinator.setRevealed(false)
        try await waitUntil { self.descendants(host).compactMap { $0 as? ShelfGIFPreviewView }.allSatisfy { !$0.isAnimating } }
    }

    private func assertReceivesPointer(_ button: NSButton, in panel: ShelfPanel, coordinator: ShelfCoordinator,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let windowPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        coordinator.updateMousePassThrough(panel.convertPoint(toScreen: windowPoint), in: panel)
        XCTAssertFalse(panel.ignoresMouseEvents, file: file, line: line)
        let content = panel.contentView!
        let hitPoint = content.superview?.convert(windowPoint, from: nil) ?? windowPoint
        XCTAssertTrue(content.hitTest(hitPoint) === button,
            "hit=\(String(describing: content.hitTest(hitPoint))) point=\(hitPoint) window=\(windowPoint) parentFlipped=\(String(describing: content.superview?.isFlipped)) button=\(button.frame)",
            file: file, line: line)
        XCTAssertTrue(button.imageHugsTitle, file: file, line: line)
        XCTAssertEqual(button.alignment, .center, file: file, line: line)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("等待真实视图布局或状态更新超时")
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func image(width: Int = 16, height: Int = 10) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    @MainActor
    private final class Fixture {
        let suite = "ShelfControlsTests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults: UserDefaults
        let storage: ShelfStorage
        var coordinator: ShelfCoordinator!
        var errors: [Error] = []
        init(edge: ShelfEdge) throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            storage = ShelfStorage(directory: directory)
            let store = ShelfEdgeStore(defaults: defaults)
            store.save(edge)
            coordinator = ShelfCoordinator(edgeStore: store, storage: storage,
                                           storageErrorHandler: { [weak self] in self?.errors.append($0) })
        }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
