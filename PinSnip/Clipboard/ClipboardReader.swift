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
        includesGIFData: Bool = false
    ) -> URL? {
        guard let data = resizedGIFForClipboard(data) else { return nil }
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

        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        if includesGIFData {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
        return url
    }

    /// Bound the final, styled image, including Retina pixels and borders.
    /// Original recordings remain untouched. Small GIFs avoid recompression.
    private static func resizedGIFForClipboard(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        // X recommends width <= 1280 and height <= 1080, even below 15 MB.
        // https://docs.x.com/x-api/media/quickstart/best-practices
        let scale = min(1, 1280.0 / Double(width), 1080.0 / Double(height))
        guard scale < 1 else { return data }
        let outputWidth = max(1, Int((Double(width) * scale).rounded(.down)))
        let outputHeight = max(1, Int((Double(height) * scale).rounded(.down)))
        let count = CGImageSourceGetCount(source)
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result, UTType.gif.identifier as CFString, count, nil
        ) else { return nil }
        if let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gif = properties[kCGImagePropertyGIFDictionary] {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)
        }
        for index in 0..<count {
            let added = autoreleasepool { () -> Bool in
                guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                      let context = CGContext(
                        data: nil, width: outputWidth, height: outputHeight,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      )
                else { return false }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
                guard let resized = context.makeImage() else { return false }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                var frameProperties: [CFString: Any] = [:]
                if let gif = properties?[kCGImagePropertyGIFDictionary] {
                    frameProperties[kCGImagePropertyGIFDictionary] = gif
                }
                CGImageDestinationAddImage(destination, resized, frameProperties as CFDictionary)
                return true
            }
            guard added else { return nil }
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }
}
