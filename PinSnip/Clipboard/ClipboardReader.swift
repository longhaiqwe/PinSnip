import AppKit
import Foundation

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
        if let text = pasteboard.string(forType: .string) {
            return .classify(text: text)
        }
        return nil
    }
}

public enum ClipboardWriter {
    @discardableResult
    public static func writeGIF(
        _ data: Data,
        to pasteboard: NSPasteboard = .general,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        let url = temporaryDirectory.appendingPathComponent("PinSnip Clipboard.gif")

        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}
