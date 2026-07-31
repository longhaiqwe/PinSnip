import AppKit
import PinSnipCore
import UniformTypeIdentifiers

@MainActor
enum CaptureOutputService {
    @discardableResult
    static func copy(
        _ image: CGImage,
        style: ShareStyle,
        to pasteboard: NSPasteboard = .general
    ) -> CGImage {
        copyRendered(render(image, style: style), to: pasteboard)
    }

    @discardableResult
    static func copyScrollingCapture(
        _ image: CGImage,
        style: ShareStyle,
        to pasteboard: NSPasteboard = .general
    ) -> CGImage {
        copyRendered(render(image, style: style), to: pasteboard)
    }

    static func render(_ image: CGImage, style: ShareStyle) -> CGImage {
        ShareCardRenderer.render(baseImage: image, style: style) ?? image
    }

    @discardableResult
    static func copyRendered(
        _ image: CGImage,
        to pasteboard: NSPasteboard = .general
    ) -> CGImage {
        let representation = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return image
    }

    static func copyGIF(_ data: Data, to pasteboard: NSPasteboard = .general) {
        if ClipboardWriter.writeGIF(data, to: pasteboard) == nil {
            NSSound.beep()
        }
    }

    @discardableResult
    static func save(_ image: CGImage, style: ShareStyle) -> CGImage? {
        let output = render(image, style: style)
        return saveRendered(
            output,
            panelTitle: "保存分享图",
            filenamePrefix: "PinSnip"
        ) ? output : nil
    }

    @discardableResult
    static func saveScrollingCapture(_ image: CGImage, style: ShareStyle) -> CGImage? {
        let output = render(image, style: style)
        return saveRendered(
            output,
            panelTitle: "保存分享长图",
            filenamePrefix: "PinSnip 长截图"
        ) ? output : nil
    }

    @discardableResult
    static func saveRendered(_ image: CGImage) -> Bool {
        saveRendered(
            image,
            panelTitle: "保存图片",
            filenamePrefix: "PinSnip"
        )
    }

    private static func saveRendered(
        _ image: CGImage,
        panelTitle: String,
        filenamePrefix: String
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = defaultFilename(prefix: filenamePrefix)
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

    @discardableResult
    static func saveGIF(_ data: Data) -> Bool {
        let panel = NSSavePanel()
        panel.title = "保存分享动图"
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
