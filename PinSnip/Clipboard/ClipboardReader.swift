import AppKit
import Foundation

public enum ClipboardReader {
    public static func read(from pasteboard: NSPasteboard = .general) -> ClipboardPayload? {
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
