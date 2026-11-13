import AppKit
import XCTest
import PinSnipCore

@MainActor
final class ShelfStorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testLegacyFilesRestoreAllCardsBeyondFormerCapacity() throws {
        let storage = ShelfStorage(directory: directory)
        for index in 0..<15 {
            let url = directory.appendingPathComponent("screenshot-\(UUID().uuidString).png")
            try png().write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: url.path)
        }
        let before = try contents()
        let restored = try storage.loadItems()
        XCTAssertEqual(restored.count, 15)
        XCTAssertEqual(Set(restored.map(\.url.lastPathComponent)), Set(before.keys))
        XCTAssertEqual(try contents(), before)
        let dates = try restored.map { try $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate! }
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testRestartRestoresOrderIdentityDimensionsAndGIFBytes() throws {
        let storage = ShelfStorage(directory: directory)
        let still = try storage.storeImage(image())
        let data = try gif()
        let animated = try ShelfItem.storeGIF(data, in: directory)
        try storage.saveOrder([still, animated])
        let restored = try ShelfStorage(directory: directory).loadItems()
        XCTAssertEqual(restored.map(\.id), [still.id, animated.id])
        XCTAssertEqual(restored.map(\.originalSize), [CGSize(width: 16, height: 10), CGSize(width: 16, height: 10)])
        XCTAssertTrue(restored[1].isAnimated)
        XCTAssertEqual(try Data(contentsOf: restored[1].url), data)
        XCTAssertEqual(restored[1].loadAnimation()?.frames.count, 2)
        XCTAssertLessThanOrEqual(restored[0].thumb.size.width, ShelfLayout.maxPhotoWidth)
    }

    func testNewFileWithoutIndexEntrySurvivesInterruptedSave() throws {
        let storage = ShelfStorage(directory: directory)
        let old = try storage.storeImage(image())
        try storage.saveOrder([old])
        let new = try storage.storeImage(image())
        XCTAssertEqual(try ShelfStorage(directory: directory).loadItems().map(\.id), [new.id, old.id])
    }

    func testTakingDownPreservesFileAndCanBeRestoredAfterRestart() throws {
        let storage = ShelfStorage(directory: directory)
        let item = try storage.storeImage(image())
        let original = try Data(contentsOf: item.url)
        try storage.saveOrder([item])
        try storage.archive(item)
        let reopened = ShelfStorage(directory: directory)
        XCTAssertTrue(try reopened.loadItems().isEmpty)
        let archived = directory.appendingPathComponent("Archive").appendingPathComponent(item.url.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: archived), original)
        try reopened.restoreArchived()
        XCTAssertEqual(try reopened.loadItems().map(\.id), [item.id])
        XCTAssertEqual(try Data(contentsOf: item.url), original)
    }

    func testClearAllArchivesImagesAndGIFAndRestoresOriginalBytes() throws {
        let storage = ShelfStorage(directory: directory)
        let items = [try storage.storeImage(image()), try ShelfItem.storeGIF(gif(), in: directory)]
        let bytes = try Dictionary(uniqueKeysWithValues: items.map { ($0.id, try Data(contentsOf: $0.url)) })
        try storage.saveOrder(items)
        let result = storage.archiveAll(items)
        XCTAssertNil(result.firstError)
        XCTAssertEqual(result.archivedIDs, Set(items.map(\.id)))
        try storage.saveOrder([])
        let reopened = ShelfStorage(directory: directory)
        XCTAssertTrue(try reopened.loadItems().isEmpty)
        try reopened.restoreArchived()
        let restored = try reopened.loadItems()
        XCTAssertEqual(Set(restored.map(\.id)), Set(items.map(\.id)))
        for item in restored { XCTAssertEqual(try Data(contentsOf: item.url), bytes[item.id]) }
        XCTAssertTrue(storage.archiveAll([]).archivedIDs.isEmpty)
    }

    func testClearAllKeepsFailedItemsAndContinuesArchivingOthers() throws {
        let storage = ShelfStorage(directory: directory)
        let external = ShelfStorage(directory: directory.appendingPathComponent("external"))
        let failed = try external.storeImage(image())
        let good = try storage.storeImage(image())
        let items = [failed, good]
        let result = storage.archiveAll(items)
        XCTAssertNotNil(result.firstError)
        XCTAssertEqual(result.archivedIDs, [good.id])
        XCTAssertEqual(items.filter { !result.archivedIDs.contains($0.id) }.map(\.id), [failed.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: good.url.path))
    }

    func testArchiveRestoreNeverOverwritesExistingScreenshot() throws {
        let storage = ShelfStorage(directory: directory)
        let item = try storage.storeImage(image())
        let original = try Data(contentsOf: item.url)
        try storage.archive(item)
        try original.write(to: item.url)
        try storage.restoreArchived()
        let restored = try storage.loadItems()
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(Set(restored.map(\.id)).count, 2)
        XCTAssertEqual(try Data(contentsOf: item.url), original)
        for item in restored { XCTAssertEqual(try Data(contentsOf: item.url), original) }
    }

    func testCorruptIndexAndUnreadableImageDoNotHideOtherCardsOrDeleteFiles() throws {
        let storage = ShelfStorage(directory: directory)
        let item = try storage.storeImage(image())
        let broken = directory.appendingPathComponent("screenshot-\(UUID().uuidString).png")
        try Data("broken".utf8).write(to: broken)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("order.json"))
        let externalLink = directory.appendingPathComponent("screenshot-\(UUID().uuidString).png")
        try FileManager.default.createSymbolicLink(at: externalLink, withDestinationURL: item.url)
        XCTAssertEqual(try storage.loadItems().map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalLink.path))
    }

    func testFailedImageWriteDoesNotCreateAnItem() throws {
        let file = directory.appendingPathComponent("not-a-folder")
        try Data().write(to: file)
        XCTAssertThrowsError(try ShelfStorage(directory: file).storeImage(image()))
    }

    private func contents() throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 10))
        return try XCTUnwrap(context.makeImage())
    }

    private func png() throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image()).representation(using: .png, properties: [:]))
    }

    private func gif() throws -> Data {
        try XCTUnwrap(AnimatedGIFEncoder.encode(frames: [
            AnimatedImage.Frame(image: image(), duration: 0.1),
            AnimatedImage.Frame(image: image(), duration: 0.2)
        ]))
    }
}
