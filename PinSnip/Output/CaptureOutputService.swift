import AppKit
import UniformTypeIdentifiers

@MainActor
enum CaptureOutputService {
    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) {
        let representation = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    @discardableResult
    static func save(_ image: CGImage) -> Bool {
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            NSSound.beep()
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法保存截图"
            alert.runModal()
            return false
        }
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PinSnip \(formatter.string(from: Date())).png"
    }
}

