// Integration checks for fresh capture pixels and deferred toolbar rendering.
// Writes only synthetic toolbar previews, never desktop captures.
import AppKit
import QuartzCore
import PinSnipCore

@main struct CaptureVisualCheck {
    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func assertGreenCenter(_ image: CGImage) {
        let pixel = image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1))!
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        precondition(rgba[0] < 40 && rgba[1] > 220 && rgba[2] < 40, "Expected fresh green marker, got \(rgba)")
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { return }
        if CGPreflightScreenCaptureAccess() {
            let marker = NSWindow(contentRect: CGRect(x: screen.frame.midX - 100, y: screen.frame.midY - 60,
                width: 200, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
            marker.isReleasedWhenClosed = false
            marker.backgroundColor = .magenta
            marker.isOpaque = true
            marker.level = .floating
            marker.orderFrontRegardless()
            marker.displayIfNeeded()
            CATransaction.flush()
            let service = ScreenCaptureService()
            service.prewarm(screen)
            try await Task.sleep(for: .milliseconds(1500))
            marker.backgroundColor = .green
            marker.displayIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(150))
            let image = try await service.capture(screen)
            precondition(image.width == Int(screen.frame.width * screen.backingScaleFactor))
            precondition(image.height == Int(screen.frame.height * screen.backingScaleFactor))
            assertGreenCenter(image)
            print("PASS: post-warm-up capture contains fresh pixels at native resolution")
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
            let recovery = CaptureRecovery<CGImage>(primaryTimeout: .milliseconds(20))
            let recovered = try await recovery.capture(primary: {
                try await Task.sleep(for: .seconds(2))
                return image
            }, fallback: { try await ScreenCaptureService.captureFallbackDisplay(id) })
            assertGreenCenter(recovered)
            print("PASS: real recovery capture contains the visible marker")
            marker.close()
        } else {
            print("SKIP: live pixel checks require existing screen capture permission")
        }
        // Synthetic source, so saved previews cannot include personal screen content.
        let context = CGContext(data: nil, width: 1280, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
        let image = context.makeImage()!
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 1280, height: 800),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let overlay = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                screenshot: image, windowCandidates: [], initialPointer: .zero, initialSelectionRect: .zero,
                purpose: .stillImage, onResult: { _ in }, onCancel: {})
            window.contentView = overlay
            window.orderFrontRegardless()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            for (type, point) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 140, y: 200)),
                (.leftMouseDragged, CGPoint(x: 1020, y: 620)), (.leftMouseUp, CGPoint(x: 1020, y: 620))] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                switch type {
                case .leftMouseDown: overlay.mouseDown(with: event)
                case .leftMouseDragged: overlay.mouseDragged(with: event)
                default: overlay.mouseUp(with: event)
                }
            }
            overlay.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let toolbar = overlay.subviews.first { descendants($0).contains { ($0 as? NSButton)?.toolTip == "完成并复制分享图" } }!
            precondition(!toolbar.isHidden)
            let buttons = descendants(toolbar).compactMap { $0 as? NSButton }
            precondition(buttons.filter { $0.toolTip == "文字" }.count == 1)
            precondition(buttons.first { $0.toolTip == "撤销（⌘Z）" }?.isEnabled == false)
            for disabled in [false, true] {
                if disabled { buttons.forEach { $0.isEnabled = false } }
                toolbar.displayIfNeeded()
                let rep = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds)!
                toolbar.cacheDisplay(in: toolbar.bounds, to: rep)
                let suffix = disabled ? "-disabled" : ""
                try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("toolbar-\(name)\(suffix).png"))
            }
            print("PASS: \(name) deferred toolbar visible, no duplicate controls, undo disabled")
            window.close()
        }
    }
}
