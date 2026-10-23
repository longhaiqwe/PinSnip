import AppKit
import Foundation
import PinSnipCore
import ImageIO
import UniformTypeIdentifiers

/// 晾衣架上的单张悬挂截图模型
@MainActor
final class ShelfItem: Identifiable, ObservableObject {
    let id: UUID
    let url: URL
    let thumb: NSImage
    let originalSize: CGSize
    let tilt: Double

    @Published var isFalling: Bool = false
    @Published var isFlying: Bool = false

    var isAnimated: Bool { url.pathExtension.lowercased() == "gif" }

    enum StorageError: Error { case invalidGIF }

    static func storeGIF(_ data: Data, in directory: URL) throws -> ShelfItem {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2 * ShelfLayout.maxPhotoWidth
              ] as CFDictionary)
        else { throw StorageError.invalidGIF }

        let id = UUID()
        let url = directory.appendingPathComponent("recording-\(id.uuidString).gif")
        try data.write(to: url, options: .atomic)
        let originalSize = CGSize(width: width.doubleValue, height: height.doubleValue)
        return ShelfItem(
            id: id, url: url,
            thumb: NSImage(cgImage: preview, size: ShelfLayout.photoSize(for: originalSize)),
            originalSize: originalSize
        )
    }

    func loadAnimation() -> AnimatedImage? {
        guard isAnimated, let data = try? Data(contentsOf: url) else { return nil }
        return AnimatedImage(data: data)
    }

    @discardableResult
    func copy(to pasteboard: NSPasteboard) -> Bool {
        if isAnimated {
            guard let data = try? Data(contentsOf: url) else { return false }
            return ClipboardWriter.writeGIF(data, to: pasteboard, includesGIFData: true) != nil
        }
        guard let image = NSImage(contentsOf: url) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([image, url as NSURL])
    }

    init(
        id: UUID = UUID(),
        url: URL,
        thumb: NSImage,
        originalSize: CGSize,
        tilt: Double = Double.random(in: -2.5...2.5)
    ) {
        self.id = id
        self.url = url
        self.thumb = thumb
        self.originalSize = originalSize
        self.tilt = tilt
    }
}
