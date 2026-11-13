// Compile with the app's capture/view sources and the matching Release core framework.
// Runs real captures and briefly presents the selection window. Never saves screen pixels.
import AppKit
import QuartzCore
import PinSnipCore

@main struct CaptureStartupBenchmark {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.main else {
            print("Screen recording permission unavailable; no permission request was made.")
            return
        }
        let service = ScreenCaptureService()
        let detector = WindowDetector()
        let prewarm = CommandLine.arguments.contains("--prewarm")
        let count = CommandLine.arguments.contains("--single") ? 1 : 6
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) { exit(2) }
        if prewarm {
            let start = CACurrentMediaTime()
            #if CAPTURE_PREWARM
            service.prewarm(screen)
            #else
            _ = try await service.capture(screen)
            #endif
            #if CAPTURE_PREWARM
            print("prewarm_schedule_ms,\((CACurrentMediaTime() - start) * 1000)")
            #else
            print("prewarm_capture_ms,\((CACurrentMediaTime() - start) * 1000)")
            #endif
            try await Task.sleep(for: .milliseconds(1500))
        }
        print("sample,permission_ms,windows_before_ms,capture_ms,windows_after_ms,create_ms,present_ms,total_ms,edit_ms,edit_events_ms,edit_render_ms")
        for index in 0..<count {
            let start = CACurrentMediaTime()
            guard CGPreflightScreenCaptureAccess() else { return }
            let permission = CACurrentMediaTime()
            let before = detector.candidates(on: screen)
            let windowsBefore = CACurrentMediaTime()
            let screenshot = try await service.capture(screen)
            let captured = CACurrentMediaTime()
            let after = detector.candidates(on: screen)
            let candidates = WindowCandidate.stableCandidates(before: before, after: after)
            let windowsAfter = CACurrentMediaTime()
            let controller = SelectionOverlayController(screen: screen, screenshot: screenshot,
                windowCandidates: candidates, initialPointer: CGPoint(x: 30, y: 30),
                initialSelectionRect: .zero, purpose: .stillImage, onResult: { _ in }, onCancel: {})
            let created = CACurrentMediaTime()
            controller.present()
            controller.window?.displayIfNeeded()
            CATransaction.flush()
            let presented = CACurrentMediaTime()
            // Also measure the first edit, so deferred work cannot hide an interaction regression.
            try await Task.sleep(for: .milliseconds(250))
            let editStart = CACurrentMediaTime()
            var editEventsEnd = editStart
            if let window = controller.window, let view = window.contentView as? SelectionOverlayView {
                for (type, point) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 80, y: 100)),
                    (.leftMouseDragged, CGPoint(x: 600, y: 500)), (.leftMouseUp, CGPoint(x: 600, y: 500))] {
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    switch type {
                    case .leftMouseDown: view.mouseDown(with: event)
                    case .leftMouseDragged: view.mouseDragged(with: event)
                    default: view.mouseUp(with: event)
                    }
                }
                editEventsEnd = CACurrentMediaTime()
                window.displayIfNeeded()
                CATransaction.flush()
            }
            let editEnd = CACurrentMediaTime()
            let values = [permission-start, windowsBefore-permission, captured-windowsBefore,
                          windowsAfter-captured, created-windowsAfter, presented-created,
                          presented-start, editEnd-editStart, editEventsEnd-editStart, editEnd-editEventsEnd]
            print("\(index)," + values.map { String(format: "%.3f", $0 * 1000) }.joined(separator: ","))
            controller.close()
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}
