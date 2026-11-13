import AppKit
import PinSnipCore
import XCTest

@MainActor
final class ShelfInteractionRecoveryTests: XCTestCase {
    func testFailedTakeDownRestoresVisibleCardAndAllowsRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ShelfStorage(directory: directory)
        let item = try storage.storeImage(image())
        let original = try Data(contentsOf: item.url)
        let archive = directory.appendingPathComponent("Archive")
        try Data("blocks archive directory".utf8).write(to: archive)
        let suite = "ShelfInteractionRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var errors: [Error] = []
        let coordinator = ShelfCoordinator(
            edgeStore: ShelfEdgeStore(defaults: defaults), storage: storage,
            storageErrorHandler: { errors.append($0) }
        )
        coordinator.items = [item]
        item.isFalling = true

        coordinator.discard(item: item)

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(coordinator.items.map(\.id), [item.id])
        XCTAssertFalse(item.isFalling, "归档失败必须恢复卡片显示及鼠标命中区域")
        XCTAssertEqual(try Data(contentsOf: item.url), original)

        try FileManager.default.removeItem(at: archive)
        item.isFalling = true
        coordinator.discard(item: item)

        XCTAssertTrue(coordinator.items.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent(item.url.lastPathComponent)), original)
    }

    func testFailedGIFStorageReportsErrorWithoutAddingCard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ShelfInteractionRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var errors: [Error] = []
        let coordinator = ShelfCoordinator(
            edgeStore: ShelfEdgeStore(defaults: defaults), storage: ShelfStorage(directory: directory),
            storageErrorHandler: { errors.append($0) }
        )

        coordinator.hangGIF(Data("invalid GIF".utf8))

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(coordinator.items.isEmpty)
    }

    func testUnavailablePinManagerDoesNotRemoveOriginalScreenshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = ShelfStorage(directory: directory)
        let item = try storage.storeImage(image())
        let suite = "ShelfInteractionRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ShelfCoordinator(edgeStore: ShelfEdgeStore(defaults: defaults), storage: storage)
        coordinator.items = [item]

        coordinator.pinToDesktop(item: item)

        XCTAssertEqual(coordinator.items.map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
    }

    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try XCTUnwrap(context.makeImage())
    }
}
