// Render production views with synthetic data; never captures the desktop or loads the user's shelf.
// Compile with the app's Capture/Hotkeys/Output/Pins/Shelf sources and PinSnipCore.
import AppKit
import SwiftUI
import PinSnipCore

@main
@MainActor
enum UXSurfacePreview {
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func snapshot(_ window: NSWindow, name: String, output: URL) throws {
        guard let view = window.contentView else { return }
        window.appearance = NSApp.appearance
        let settlesCards = name.hasPrefix("shelf-filled") || name.hasPrefix("shelf-undo")
        RunLoop.main.run(until: Date().addingTimeInterval(settlesCards ? 1.5 : 0.1))
        view.layoutSubtreeIfNeeded()
        ([view] + descendants(view)).forEach { $0.needsDisplay = true }
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Cannot render \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Content-view caching excludes the window's background. Composite that
        // background explicitly so transparent black text remains inspectable.
        let context = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        let bounds = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        context.fill(bounds)
        context.draw(rep.cgImage!, in: bounds)
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(
            to: output.appendingPathComponent(name + ".png"))
        print("Rendered \(name): \(Int(view.bounds.width)) × \(Int(view.bounds.height)) pt")
    }

    static func image(width: Int = 640, height: Int = 360) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.18, green: 0.42, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 24, y: 24, width: width / 2, height: height - 48))
        return context.makeImage()!
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { fatalError("No screen") }
        let suite = "PinSnip.UXPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let temporaryStorage = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: temporaryStorage) }

        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let hotkeys = HotKeySettingsWindowController(settings: .standard, applyHandler: { _ in false })
            try snapshot(hotkeys.window!, name: "hotkeys-\(theme)", output: output)
            let save = descendants(hotkeys.window!.contentView!).compactMap { $0 as? NSButton }
                .first { $0.title == "保存" }!
            save.performClick(nil)
            try snapshot(hotkeys.window!, name: "hotkeys-error-\(theme)", output: output)
            hotkeys.close()

            let sharing = GIFShareSettingsWindowController(store: GIFShareSettingsStore(defaults: defaults))
            try snapshot(sharing.window!, name: "gif-settings-\(theme)", output: output)
            let fields = descendants(sharing.window!.contentView!).compactMap { $0 as? NSTextField }
            fields.first { $0.isEditable }!.stringValue = "invalid"
            descendants(sharing.window!.contentView!).compactMap { $0 as? NSButton }
                .first { $0.title == "保存" }!.performClick(nil)
            try snapshot(sharing.window!, name: "gif-settings-error-\(theme)", output: output)
            sharing.close()

            let recording = GIFRecordingPanelController(screen: screen,
                selectionRect: CGRect(x: 100, y: 100, width: 640, height: 360))
            recording.recordingDidStart()
            try snapshot(recording.window!, name: "recording-active-\(theme)", output: output)
            recording.showExporting()
            try snapshot(recording.window!, name: "recording-exporting-\(theme)", output: output)
            recording.finish()

            let recovery = GIFOutputRecoveryController(data: Data([0]), result: .cancelled,
                copyHandler: { _, _ in }, saveHandler: { _ in .cancelled })
            try snapshot(recovery.window!, name: "recording-recovery-\(theme)", output: output)
            recovery.retryCopy()
            try snapshot(recovery.window!, name: "recording-recovery-disabled-\(theme)", output: output)
            recovery.close()

            let scrolling = ScrollingCapturePanelController(screen: screen,
                selectionRect: CGRect(x: 100, y: 100, width: 640, height: 360), mode: .automatic)
            try snapshot(scrolling.window!, name: "scrolling-preparing-\(theme)", output: output)
            scrolling.update(frameCount: 12, pixelHeight: 7800)
            try snapshot(scrolling.window!, name: "scrolling-active-\(theme)", output: output)
            scrolling.showManualScrollingRequired()
            try snapshot(scrolling.window!, name: "scrolling-manual-\(theme)", output: output)
            scrolling.showAlignmentLost()
            try snapshot(scrolling.window!, name: "scrolling-alignment-\(theme)", output: output)
            scrolling.showExporting()
            try snapshot(scrolling.window!, name: "scrolling-exporting-\(theme)", output: output)
            scrolling.finish()

            for width in [375, 600, 1280] {
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 800),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: width, height: 800),
                    screenshot: image(width: width, height: 800), windowCandidates: [], initialPointer: .zero,
                    initialSelectionRect: CGRect(x: 30, y: 160, width: width - 60, height: 400),
                    purpose: .stillImage, onResult: { _ in }, onCancel: {})
                try snapshot(window, name: "selection-\(width)-\(theme)", output: output)
                window.close()
            }

            for edge in ShelfEdge.allCases {
                let edgeStore = ShelfEdgeStore(defaults: defaults)
                edgeStore.save(edge)
                let coordinator = ShelfCoordinator(edgeStore: edgeStore, storage: ShelfStorage(directory: temporaryStorage))
                coordinator.setRevealed(true)
                let size = edge.isVertical ? CGSize(width: 210, height: 700) : CGSize(width: 1000, height: 210)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: ShelfView(coordinator: coordinator))
                host.frame = CGRect(origin: .zero, size: size)
                window.contentView = host
                try snapshot(window, name: "shelf-empty-\(edge.rawValue)-\(theme)", output: output)
                // Populate only this isolated coordinator; do not call start() or shared.
                coordinator.items = try [(640, 360), (200, 500), (800, 120)].map {
                    try ShelfStorage(directory: temporaryStorage).storeImage(image(width: $0.0, height: $0.1))
                }
                let populated = NSHostingView(rootView: ShelfView(coordinator: coordinator))
                populated.frame = CGRect(origin: .zero, size: size)
                window.contentView = populated
                try snapshot(window, name: "shelf-filled-\(edge.rawValue)-\(theme)", output: output)
                coordinator.beginDragging(item: coordinator.items[0])
                try snapshot(window, name: "shelf-disabled-\(edge.rawValue)-\(theme)", output: output)
                coordinator.endDragging()
                coordinator.clearAll()
                try snapshot(window, name: "shelf-undo-\(edge.rawValue)-\(theme)", output: output)
                window.close()
            }
        }
    }
}
