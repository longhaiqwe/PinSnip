import AppKit
import PinSnipCore
import UniformTypeIdentifiers

enum CaptureOutputResult {
    case succeeded
    case cancelled
    case failed(Error)

    var succeeded: Bool {
        if case .succeeded = self { return true }
        return false
    }
}

@MainActor
enum CaptureOutputService {
    @discardableResult
    static func copy(
        _ image: CGImage,
        style: ShareStyle,
        borderSize: ShareBorderSize = .automatic,
        to pasteboard: NSPasteboard = .general
    ) -> CGImage {
        copyRendered(render(image, style: style, borderSize: borderSize), to: pasteboard)
    }

    @discardableResult
    static func copyScrollingCapture(
        _ image: CGImage,
        style: ShareStyle,
        borderSize: ShareBorderSize = .automatic,
        to pasteboard: NSPasteboard = .general
    ) -> CGImage {
        copyRendered(render(image, style: style, borderSize: borderSize), to: pasteboard)
    }

    static func render(_ image: CGImage, style: ShareStyle, borderSize: ShareBorderSize = .automatic) -> CGImage {
        ShareCardRenderer.render(baseImage: image, style: style, borderSize: borderSize) ?? image
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

    private static var isCopyingGIF = false

    static func copyGIF(
        _ data: Data,
        to pasteboard: NSPasteboard = .general,
        reportError: Bool = true,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        copyGIFResult(data, to: pasteboard, reportError: reportError) {
            completion($0.succeeded)
        }
    }

    static func copyGIFResult(
        _ data: Data,
        to pasteboard: NSPasteboard = .general,
        reportError: Bool = false,
        completion: @escaping (CaptureOutputResult) -> Void
    ) {
        guard !isCopyingGIF else {
            completion(.failed(NSError(domain: "PinSnip.Output", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "另一张动图仍在处理，请稍后重试。"])))
            return
        }
        isCopyingGIF = true
        let settings = GIFShareSettingsStore().load()
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 90),
                               styleMask: [.titled], backing: .buffered, defer: false)
        progress.title = "准备分享动图"
        progress.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 33, width: 24, height: 24))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: "正在按设置压缩，请稍候…")
        label.frame = NSRect(x: 62, y: 35, width: 220, height: 20)
        progress.contentView?.addSubview(spinner)
        progress.contentView?.addSubview(label)
        progress.center()
        progress.orderFrontRegardless()
        Task {
            let result: CaptureOutputResult
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try GIFShareEncoder.encode(data, settings: settings)
                }.value
                guard ClipboardWriter.writePreparedGIF(prepared, to: pasteboard, includesGIFData: true) != nil else {
                    throw CocoaError(.fileWriteUnknown)
                }
                result = .succeeded
            } catch {
                result = .failed(error)
            }
            isCopyingGIF = false
            progress.close()
            if reportError, case let .failed(error) = result {
                let alert = NSAlert(error: error)
                alert.messageText = "无法复制动图"
                alert.runModal()
            }
            completion(result)
        }
    }

    @discardableResult
    static func save(_ image: CGImage, style: ShareStyle, borderSize: ShareBorderSize = .automatic) -> CGImage? {
        let output = render(image, style: style, borderSize: borderSize)
        return saveRendered(
            output,
            panelTitle: "保存分享图",
            filenamePrefix: "PinSnip"
        ) ? output : nil
    }

    @discardableResult
    static func saveScrollingCapture(_ image: CGImage, style: ShareStyle, borderSize: ShareBorderSize = .automatic) -> CGImage? {
        let output = render(image, style: style, borderSize: borderSize)
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

    @discardableResult
    static func saveRendered(
        _ image: CGImage,
        panelTitle: String,
        filenamePrefix: String
    ) -> Bool {
        saveRenderedResult(image, panelTitle: panelTitle, filenamePrefix: filenamePrefix).succeeded
    }

    static func saveRenderedResult(
        _ image: CGImage,
        panelTitle: String,
        filenamePrefix: String,
        reportError: Bool = true
    ) -> CaptureOutputResult {
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.nameFieldStringValue = defaultFilename(prefix: filenamePrefix)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let representation = NSBitmapImageRep(cgImage: image)
        let result: CaptureOutputResult
        if let data = representation.representation(using: .png, properties: [:]) {
            result = write(data, to: url)
        } else {
            result = .failed(CocoaError(.fileWriteUnknown))
        }
        if reportError, case let .failed(error) = result {
            let alert = NSAlert(error: error)
            alert.messageText = "无法保存截图"
            alert.runModal()
        }
        return result
    }

    @discardableResult
    static func saveGIF(_ data: Data) -> Bool {
        saveGIFResult(data, reportError: true).succeeded
    }

    static func saveGIFResult(_ data: Data, reportError: Bool = false) -> CaptureOutputResult {
        let panel = NSSavePanel()
        panel.title = "保存分享动图"
        panel.nameFieldStringValue = defaultFilename(fileExtension: "gif")
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let result = write(data, to: url)
        if reportError, case let .failed(error) = result {
            let alert = NSAlert(error: error)
            alert.messageText = "无法保存动图"
            alert.runModal()
        }
        return result
    }

    static func write(_ data: Data, to url: URL) -> CaptureOutputResult {
        do {
            try data.write(to: url, options: .atomic)
            return .succeeded
        } catch {
            return .failed(error)
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
