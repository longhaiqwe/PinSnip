import AppKit
import PinSnipCore

@MainActor
final class PinWindowManager {
    private var controllers: [PinWindowController] = []

    var count: Int { controllers.count }

    @discardableResult
    func pin(_ image: CGImage, near point: NSPoint = NSEvent.mouseLocation) -> PinWindowController {
        let offset = CGFloat(controllers.count % 8) * 18
        let origin = NSPoint(x: point.x + 18 + offset, y: point.y - min(420, CGFloat(image.height)) - offset)
        let controller = PinWindowController(image: image, origin: origin)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        controller.show()
        return controller
    }

    @discardableResult
    func pinClipboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = ClipboardReader.read(from: pasteboard),
              let image = ClipboardCardRenderer.image(for: payload)
        else {
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
