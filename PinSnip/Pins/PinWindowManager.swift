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
        retainAndShow(controller)
        return controller
    }

    @discardableResult
    func pin(_ animation: AnimatedImage, near point: NSPoint = NSEvent.mouseLocation) -> PinWindowController {
        let offset = CGFloat(controllers.count % 8) * 18
        let origin = NSPoint(
            x: point.x + 18 + offset,
            y: point.y - min(420, CGFloat(animation.pixelHeight)) - offset
        )
        let controller = PinWindowController(animation: animation, origin: origin)
        retainAndShow(controller)
        return controller
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
