import AppKit
import ImageIO
import PinSnipCore
import UniformTypeIdentifiers

/// The media files are authoritative. The index only preserves the user's order.
@MainActor
final class ShelfStorage {
    struct ArchivedItem {
        let url: URL
        fileprivate let item: ShelfItem
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PinSnip/Shelf", isDirectory: true)
    }

    let directory: URL
    private let fileManager = FileManager.default
    private var orderURL: URL { directory.appendingPathComponent("order.json") }
    private var archiveDirectory: URL { directory.appendingPathComponent("Archive", isDirectory: true) }

    init(directory: URL = ShelfStorage.defaultDirectory) {
        self.directory = directory
    }

    func loadItems() throws -> [ShelfItem] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try mediaFiles(in: directory)
        let order = (try? Data(contentsOf: orderURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let indexedNames = Set(order)
        // Files saved immediately before a crash may not have an index entry yet.
        let newURLs = urls.filter { !indexedNames.contains($0.lastPathComponent) }
        let byName = Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, $0) })
        var seen = Set<UUID>()
        return (newURLs + order.compactMap { byName[$0] }).compactMap { url in
            guard let item = loadItem(at: url), seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    func storeImage(_ image: CGImage) throws -> ShelfItem {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let url = directory.appendingPathComponent("screenshot-\(id.uuidString).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
        guard let item = loadItem(at: url) else { throw CocoaError(.fileReadCorruptFile) }
        return item
    }

    func saveOrder(_ items: [ShelfItem]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items.map(\.url.lastPathComponent)).write(to: orderURL, options: .atomic)
    }

    @discardableResult
    func archive(_ item: ShelfItem) throws -> ArchivedItem? {
        guard item.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        // Finder may already have moved the original out of the shelf.
        guard fileManager.fileExists(atPath: item.url.path) else { return nil }
        try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let destination = availableDestination(for: item.url, in: archiveDirectory)
        try fileManager.moveItem(at: item.url, to: destination)
        return ArchivedItem(url: destination, item: item)
    }

    /// 单个文件失败不影响其他文件；调用方只移除已成功归档的卡片。
    func archiveAll(_ items: [ShelfItem]) -> (archivedIDs: Set<UUID>, archivedItems: [UUID: ArchivedItem], firstError: Error?) {
        var archivedIDs = Set<UUID>()
        var archivedItems: [UUID: ArchivedItem] = [:]
        var firstError: Error?
        for item in items {
            do {
                archivedItems[item.id] = try archive(item)
                archivedIDs.insert(item.id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return (archivedIDs, archivedItems, firstError)
    }

    /// 只恢复指定批次的文件，不把历史归档一起挂回。
    func restoreArchivedItem(_ archived: ArchivedItem) throws -> ShelfItem {
        let url = archived.url
        guard url.deletingLastPathComponent().standardizedFileURL == archiveDirectory.standardizedFileURL
        else { throw CocoaError(.fileReadNoPermission) }
        let fingerprint = ShelfItem.FileFingerprint(at: url)
        let preview: ShelfItem
        if let fingerprint, fingerprint == archived.item.fileFingerprint {
            preview = archived.item
        } else {
            let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink == false, let decoded = loadItem(at: url)
            else { throw CocoaError(.fileReadCorruptFile) }
            preview = decoded
        }
        let destination = availableDestination(for: url, in: directory)
        guard let id = identifier(for: destination) else { throw CocoaError(.fileReadCorruptFile) }
        try fileManager.moveItem(at: url, to: destination)
        return ShelfItem(id: id, url: destination, thumb: preview.thumb, originalSize: preview.originalSize,
                         tilt: archived.item.tilt, animatesOnAppearance: false)
    }

    func restoreArchived() throws {
        guard fileManager.fileExists(atPath: archiveDirectory.path) else { return }
        for url in try mediaFiles(in: archiveDirectory) {
            try fileManager.moveItem(at: url, to: availableDestination(for: url, in: directory))
        }
    }

    private func availableDestination(for url: URL, in folder: URL) -> URL {
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        while fileManager.fileExists(atPath: destination.path) {
            let prefix = url.pathExtension.lowercased() == "gif" ? "recording" : "screenshot"
            destination = folder.appendingPathComponent("\(prefix)-\(UUID().uuidString).\(url.pathExtension)")
        }
        return destination
    }

    private func identifier(for url: URL) -> UUID? {
        let ext = url.pathExtension.lowercased()
        guard ext == "png" || ext == "gif" else { return nil }
        let prefix = ext == "gif" ? "recording-" : "screenshot-"
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }

    private func mediaFiles(in folder: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
        return files.compactMap { url -> (URL, Date)? in
            guard identifier(for: url) != nil,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted {
            $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1
        }.map(\.0)
    }

    private func loadItem(at url: URL) -> ShelfItem? {
        guard let id = identifier(for: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2 * ShelfLayout.maxPhotoWidth
              ] as CFDictionary) else { return nil }
        let size = CGSize(width: width.doubleValue, height: height.doubleValue)
        return ShelfItem(id: id, url: url,
                         thumb: NSImage(cgImage: thumbnail, size: ShelfLayout.photoSize(for: size)),
                         originalSize: size)
    }
}
