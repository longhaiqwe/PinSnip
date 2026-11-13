import AppKit
import PinSnipCore

@MainActor
final class PinWindowManager {
    private var controllers: [PinWindowController] = []

    var count: Int { controllers.count }
    var hasClickThroughPins: Bool {
        controllers.contains { $0.isClickThroughEnabled }
    }

    @discardableResult
    func pin(_ image: CGImage, near point: NSPoint = NSEvent.mouseLocation) -> PinWindowController {
        let frame = initialFrame(for: NSSize(width: image.width, height: image.height), near: point)
        let controller = PinWindowController(image: image, frame: frame)
        retainAndShow(controller)
        return controller
    }

    @discardableResult
    func pin(_ animation: AnimatedImage, near point: NSPoint = NSEvent.mouseLocation) -> PinWindowController {
        let frame = initialFrame(
            for: NSSize(width: animation.pixelWidth, height: animation.pixelHeight), near: point
        )
        let controller = PinWindowController(animation: animation, frame: frame)
        retainAndShow(controller)
        return controller
    }

    private func initialFrame(for imageSize: NSSize, near point: NSPoint) -> NSRect {
        // 用完整屏幕范围定位显示器，鼠标位于 Dock 或菜单栏时也能选中正确屏幕。
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: point.x - 400, y: point.y - 300, width: 800, height: 600)
        return PinWindowLayout.initialFrame(
            imageSize: imageSize, visibleFrame: visibleFrame, cascadeIndex: controllers.count
        )
    }

    private func retainAndShow(_ controller: PinWindowController) {
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.show()
    }

    @discardableResult
    func pinClipboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = ClipboardReader.read(from: pasteboard) else {
            NSSound.beep()
            return false
        }

        switch payload {
        case let .animatedImageData(data):
            if let animation = AnimatedImage(data: data) {
                pin(animation)
                return true
            }
        case let .file(url):
            if url.pathExtension.lowercased() == "gif",
               let data = try? Data(contentsOf: url),
               let animation = AnimatedImage(data: data) {
                pin(animation)
                return true
            }
        default:
            break
        }

        guard let image = ClipboardCardRenderer.image(for: payload) else {
            NSSound.beep()
            return false
        }
        pin(image)
        return true
    }

    func hideAll() {
        controllers.forEach { $0.setHidden(true) }
    }

    func showAll() {
        controllers.forEach { $0.setHidden(false) }
    }

    func makeAllInteractive() {
        controllers.forEach { $0.makeInteractive() }
    }
}
