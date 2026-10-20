import AppKit
import XCTest
import PinSnipCore

final class MenuHotKeyTests: XCTestCase {
    @MainActor
    private final class TimerAction: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    @MainActor
    func testRealContextMenuReceivesF1AndExitsAfterSnapshot() throws {
        try exerciseRealMenu(statusItem: false)
    }

    @MainActor
    func testRealStatusItemMenuReceivesF1AndExitsAfterSnapshot() throws {
        try exerciseRealMenu(statusItem: true)
    }

    @MainActor
    private func exerciseRealMenu(statusItem: Bool) throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFrontRegardless()
        let menu = NSMenu()
        menu.addItem(withTitle: "Menu capture regression", action: nil, keyEquivalent: "")
        let image = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        var received: [GlobalHotKeyCenter.Identifier] = []
        var session: MenuCaptureSession?
        var delivered = false
        var center: GlobalHotKeyCenter!
        center = GlobalHotKeyCenter { identifier in
            received.append(identifier)
            XCTAssertTrue(center.trackingMenus.contains { $0 === menu })
            let capture = MenuCaptureSession(menus: center.trackingMenus)
            session = capture
            capture.start(capture: { image }) { _ in delivered = true }
        }
        defer {
            center.shutdown(); center = nil; session?.cancel()
            while NSApp.nextEvent(matching: [.keyDown, .keyUp], until: nil,
                                  inMode: .eventTracking, dequeue: true) != nil {}
        }
        XCTAssertTrue(center.register(.standard))
        let keyEvent = key(122, flags: [.function])
        let triggerAction = TimerAction { NSApp.postEvent(keyEvent, atStart: true) }
        let trigger = Timer(timeInterval: 0.05, target: triggerAction,
                            selector: #selector(TimerAction.fire), userInfo: nil, repeats: false)
        var timedOut = false
        let watchdogAction = TimerAction { timedOut = true; menu.cancelTrackingWithoutAnimation() }
        let watchdog = Timer(timeInterval: 1, target: watchdogAction,
                             selector: #selector(TimerAction.fire), userInfo: nil, repeats: false)
        RunLoop.main.add(trigger, forMode: .common)
        RunLoop.main.add(watchdog, forMode: .common)
        defer { trigger.invalidate(); watchdog.invalidate() }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 20, y: 20),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        if statusItem {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            defer { NSStatusBar.system.removeStatusItem(item) }
            item.button?.title = "T"
            item.menu = menu
            try XCTUnwrap(item.button).performClick(nil)
        } else {
            NSMenu.popUpContextMenu(menu, with: event, for: window.contentView!)
        }
        XCTAssertFalse(timedOut, "The hotkey must work inside a real NSMenu tracking loop")
        XCTAssertEqual(received, [.capture])
        XCTAssertTrue(center.trackingMenus.isEmpty)
        let deadline = Date().addingTimeInterval(1)
        while !delivered && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(delivered)
    }

    @MainActor
    func testScreenshotKeyIsDeliveredWhileContextMenuIsTracking() {
        _ = NSApplication.shared
        var received: [GlobalHotKeyCenter.Identifier] = []
        let center = GlobalHotKeyCenter { received.append($0) }
        defer { center.shutdown() }
        XCTAssertTrue(center.register(.standard))
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        defer { NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu) }

        NSApp.sendEvent(key(122, flags: [.function]))
        XCTAssertEqual(received, [.capture], "F1 must reach capture before the menu closes")
    }

    @MainActor
    func testMenuUsesConfiguredShortcutAndIgnoresRepeatsAndOtherKeys() {
        _ = NSApplication.shared
        var received: [GlobalHotKeyCenter.Identifier] = []
        let center = GlobalHotKeyCenter { received.append($0) }
        defer { center.shutdown() }
        XCTAssertTrue(center.register(HotKeySettings(
            capture: HotKeyShortcut(keyCode: 8, modifiers: [.command, .shift]),
            recording: HotKeySettings.standard.recording,
            paste: HotKeySettings.standard.paste
        )))
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        NSApp.sendEvent(key(122, flags: [.function]))
        NSApp.sendEvent(key(8, flags: [.command]))
        NSApp.sendEvent(key(8, flags: [.command, .shift], repeatKey: true))
        XCTAssertTrue(received.isEmpty)
        NSApp.sendEvent(key(8, flags: [.command, .shift, .capsLock]))
        XCTAssertEqual(received, [.capture])
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        NSApp.sendEvent(key(8, flags: [.command, .shift]))
        XCTAssertEqual(received, [.capture], "The menu fallback must stop when tracking ends")
    }

    @MainActor
    func testTrackingRunLoopHandlesKeysWithoutAppKitDispatch() {
        _ = NSApplication.shared
        var received: [GlobalHotKeyCenter.Identifier] = []
        let center = GlobalHotKeyCenter { received.append($0) }
        defer { center.shutdown() }
        XCTAssertTrue(center.register(.standard))
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        defer { NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu) }
        NSApp.postEvent(key(99, flags: [.function]), atStart: true)
        let deadline = Date().addingTimeInterval(0.2)
        while received.isEmpty && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(received, [.recording])
        // Remove an unhandled test event on the failing baseline.
        _ = NSApp.nextEvent(matching: .keyDown, until: nil, inMode: .eventTracking, dequeue: true)
    }

    @MainActor
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags, repeatKey: Bool = false) -> NSEvent {
        let characters = code == 122 ? "\u{F704}" : (code == 99 ? "\u{F706}" : "c")
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                        timestamp: 0, windowNumber: 0, context: nil,
                        characters: characters, charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code)!
    }
}
