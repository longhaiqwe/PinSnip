import AppKit
import Foundation
import PinSnipCore
import ImageIO
import UniformTypeIdentifiers

/// 晾衣架上的单张悬挂截图模型
@MainActor
final class ShelfItem: Identifiable, ObservableObject {
    static let pasteboardType = NSPasteboard.PasteboardType("com.longhai.pinsnip.shelf-item")
    let id: UUID
    let url: URL
    let thumb: NSImage
    let originalSize: CGSize
    let tilt: Double
    let animatesOnAppearance: Bool
    let fileFingerprint: FileFingerprint?

    @Published var isFalling: Bool = false

    var isAnimated: Bool { url.pathExtension.lowercased() == "gif" }

    enum StorageError: Error { case invalidGIF }

    struct FileFingerprint: Equatable {
        let identifier: NSObject
        let modifiedAt: Date
        let size: Int

        init?(at url: URL) {
            // Use a fresh URL so cached metadata cannot hide a replaced file.
            guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileResourceIdentifierKey,
                .contentModificationDateKey, .fileSizeKey,
            ]), values.isRegularFile == true, values.isSymbolicLink == false,
                  let identifier = values.fileResourceIdentifier as? NSObject,
                  let modifiedAt = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            self.identifier = identifier
            self.modifiedAt = modifiedAt
            self.size = size
        }
    }

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

    func draggingPasteboardItem() -> NSPasteboardItem? {
        let writer: NSPasteboardItem
        if isAnimated {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            writer = ClipboardWriter.gifPasteboardItem(data, fileURL: url)
        } else {
            writer = NSPasteboardItem()
            writer.setString(url.absoluteString, forType: .fileURL)
        }
        writer.setString(id.uuidString, forType: Self.pasteboardType)
        return writer
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
        tilt: Double = Double.random(in: -2.5...2.5),
        animatesOnAppearance: Bool = true
    ) {
        self.id = id
        self.url = url
        self.thumb = thumb
        self.originalSize = originalSize
        self.tilt = tilt
        self.animatesOnAppearance = animatesOnAppearance
        self.fileFingerprint = FileFingerprint(at: url)
    }
}
