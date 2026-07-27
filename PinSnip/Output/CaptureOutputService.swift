import AppKit
import PinSnipCore
import UniformTypeIdentifiers

@MainActor
enum CaptureOutputService {
    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) {
        copy(image, decorates: true, to: pasteboard)
    }

    static func copyScrollingCapture(
        _ image: CGImage,
        to pasteboard: NSPasteboard = .general
    ) {
        copy(image, decorates: false, to: pasteboard)
    }

    private static func copy(
        _ image: CGImage,
        decorates: Bool,
        to pasteboard: NSPasteboard
    ) {
        let output = decorates
            ? ShareCardRenderer.render(baseImage: image) ?? image
            : image
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
        save(
            image,
            decorates: true,
            panelTitle: "保存截图",
            filenamePrefix: "PinSnip"
        )
    }

    @discardableResult
    static func saveScrollingCapture(_ image: CGImage) -> Bool {
        save(
            image,
            decorates: false,
            panelTitle: "保存滚动截屏",
            filenamePrefix: "PinSnip 长截图"
        )
    }

    private static func save(
        _ image: CGImage,
        decorates: Bool,
        panelTitle: String,
        filenamePrefix: String
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = defaultFilename(prefix: filenamePrefix)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let output = decorates
            ? ShareCardRenderer.render(baseImage: image) ?? image
            : image
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

    private static func defaultFilename(
        prefix: String = "PinSnip",
        fileExtension: String = "png"
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: Date())).\(fileExtension)"
    }
}
