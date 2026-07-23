import AppKit
import PinSnipCore
import UniformTypeIdentifiers

@MainActor
enum CaptureOutputService {
    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) {
        let output = ShareCardRenderer.render(baseImage: image) ?? image
        let representation = NSBitmapImageRep(cgImage: output)
        let nsImage = NSImage(
            cgImage: output,
            size: NSSize(width: output.width, height: output.height)
        )
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    static func copyGIF(_ data: Data, to pasteboard: NSPasteboard = .general) {
        if ClipboardWriter.writeGIF(data, to: pasteboard) == nil {
            NSSound.beep()
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

        let output = ShareCardRenderer.render(baseImage: image) ?? image
        let representation = NSBitmapImageRep(cgImage: output)
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

    @discardableResult
    static func saveGIF(_ data: Data) -> Bool {
        let panel = NSSavePanel()
        panel.title = "保存动图"
        panel.nameFieldStringValue = defaultFilename(fileExtension: "gif")
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法保存动图"
            alert.runModal()
            return false
        }
    }

    private static func defaultFilename(fileExtension: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PinSnip \(formatter.string(from: Date())).\(fileExtension)"
    }
}
