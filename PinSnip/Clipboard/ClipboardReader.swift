import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardReader {
    private static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

    public static func read(from pasteboard: NSPasteboard = .general) -> ClipboardPayload? {
        if let gif = pasteboard.data(forType: gifType) {
            return .animatedImageData(gif)
        }
        if let png = pasteboard.data(forType: .png) {
            return .imageData(png)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return .imageData(tiff)
        }
        if let value = pasteboard.propertyList(forType: .fileURL) as? String,
           let url = URL(string: value) {
            return .file(url)
        }
        return nil
    }
}

public enum ClipboardWriter {
    @discardableResult
    public static func writeGIF(
        _ data: Data,
        to pasteboard: NSPasteboard = .general,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        includesGIFData: Bool = true,
        defaults: UserDefaults = .standard
    ) -> URL? {
        guard let data = try? GIFShareEncoder.encode(data, settings: GIFShareSettingsStore(defaults: defaults).load()) else { return nil }
        return writePreparedGIF(data, to: pasteboard, temporaryDirectory: temporaryDirectory, includesGIFData: includesGIFData)
    }

    /// Writes already prepared bytes without recompressing them.
    @discardableResult
    public static func writePreparedGIF(
        _ data: Data,
        to pasteboard: NSPasteboard = .general,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        includesGIFData: Bool = true
    ) -> URL? {
        // Keep each copied file stable for browsers that read it asynchronously.
        let url = temporaryDirectory.appendingPathComponent("PinSnip Clipboard-\(UUID().uuidString).gif")

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        let item = gifPasteboardItem(data, fileURL: url, includesGIFData: includesGIFData)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// One animated image with a file fallback, shared by copy and drag export.
    /// Never advertise PNG/TIFF: receivers may select them and lose the animation.
    public static func gifPasteboardItem(
        _ data: Data,
        fileURL: URL,
        includesGIFData: Bool = true
    ) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if includesGIFData {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
            // Qt 5's QMacPasteboardMimeAny maps this UTI to image/gif without
            // decoding a frame. Its built-in image converter only handles TIFF.
            // https://github.com/qt/qtbase/blob/5.15/src/platformsupport/clipboard/qmacmime.mm
            item.setData(data, forType: NSPasteboard.PasteboardType("com.trolltech.anymime.image--gif"))
        }
        item.setString(fileURL.absoluteString, forType: .fileURL)
        return item
    }
}
