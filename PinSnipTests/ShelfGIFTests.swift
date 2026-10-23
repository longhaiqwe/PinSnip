import AppKit
import XCTest
import PinSnipCore

final class ShelfGIFTests: XCTestCase {
    @MainActor
    func testShelfPreviewPlaysEveryFrameLoopsAndStopsWhenHidden() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = try ShelfItem.storeGIF(makeGIF(), in: folder)
        let window = NSWindow(contentRect: CGRect(x: 20, y: 20, width: 136, height: 104), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let preview = ShelfGIFPreviewView(frame: CGRect(x: 0, y: 0, width: 136, height: 104))
        preview.configure(url: item.url, placeholder: item.thumb, isPlaying: true)
        XCTAssertFalse(preview.isAnimating, "Detached previews must not start timers")
        window.contentView = preview
        window.orderFrontRegardless()
        defer { preview.stopPlayback(); window.close() }
        preview.configure(url: item.url, placeholder: item.thumb, isPlaying: true)
        XCTAssertTrue(preview.isAnimating)
        try await waitForFrame(1, in: preview)
        let image = try XCTUnwrap(preview.image)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let color = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.85, "The second frame must actually be rendered")
        try await waitForFrame(0, in: preview)

        preview.configure(url: item.url, placeholder: item.thumb, isPlaying: false)
        XCTAssertFalse(preview.isAnimating)
        let stoppedFrame = preview.frameIndex
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(preview.frameIndex, stoppedFrame)

        preview.configure(url: item.url, placeholder: item.thumb, isPlaying: true)
        try await waitForFrame(1, in: preview)
        preview.removeFromSuperview()
        XCTAssertFalse(preview.isAnimating, "Removing a card must invalidate its timer")
    }

    @MainActor
    func testPreviewDecodesOnlyThumbnailSizedFrames() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try makeGIF(width: 640, height: 480)
        let item = try ShelfItem.storeGIF(data, in: folder)
        let window = NSWindow(contentRect: CGRect(x: 20, y: 20, width: 136, height: 104), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let preview = ShelfGIFPreviewView(frame: .zero)
        window.contentView = preview
        defer { preview.stopPlayback(); window.close() }
        preview.configure(url: item.url, placeholder: item.thumb, isPlaying: true)
        let image = try XCTUnwrap(preview.image)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        XCTAssertLessThanOrEqual(bitmap.pixelsWide, ShelfGIFPreviewView.maximumThumbnailDimension)
        XCTAssertLessThanOrEqual(bitmap.pixelsHigh, ShelfGIFPreviewView.maximumThumbnailDimension)
        XCTAssertEqual(try Data(contentsOf: item.url), data)
    }

    @MainActor
    private func waitForFrame(_ frame: Int, in preview: ShelfGIFPreviewView) async throws {
        for _ in 0..<100 {
            if preview.frameIndex == frame { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Animated preview did not advance to frame \(frame)")
    }

    @MainActor
    func testStoredRecordingRetainsOriginalGIFAndLoadsEveryFrameForPinning() throws {
        let data = try makeGIF()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let item = try ShelfItem.storeGIF(data, in: folder)
        XCTAssertTrue(item.isAnimated)
        XCTAssertEqual(item.url.pathExtension, "gif")
        XCTAssertEqual(try Data(contentsOf: item.url), data, "Drag export must keep the original animated file")
        XCTAssertEqual(item.originalSize, CGSize(width: 4, height: 3))
        XCTAssertGreaterThan(item.thumb.size.width, 0)
        let animation = try XCTUnwrap(item.loadAnimation())
        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(animation.frames[0].duration, 0.1, accuracy: 0.01)
        XCTAssertEqual(animation.frames[1].duration, 0.2, accuracy: 0.01)
        XCTAssertEqual(animation.loopCount, 0)
    }

    @MainActor
    func testInvalidRecordingAndFailedWriteDoNotProduceShelfItems() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try ShelfItem.storeGIF(Data("invalid".utf8), in: folder))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        XCTAssertThrowsError(try ShelfItem.storeGIF(makeGIF(), in: folder.appendingPathComponent("missing")))
    }

    @MainActor
    func testCopyingShelfGIFPreservesAnimationInsteadOfFlatteningToTIFF() throws {
        let data = try makeGIF()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("recording.gif")
        try data.write(to: url)
        let item = ShelfItem(url: url, thumb: try XCTUnwrap(NSImage(data: data)), originalSize: CGSize(width: 4, height: 3))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(item.copy(to: pasteboard))
        guard case .animatedImageData(let copied) = ClipboardReader.read(from: pasteboard) else {
            return XCTFail("Copying an animated shelf item must offer the original GIF, not a still image")
        }
        XCTAssertEqual(copied, data)
        XCTAssertEqual(try XCTUnwrap(AnimatedImage(data: copied)).frames.count, 2)
        let copiedURL = try XCTUnwrap(URL(string: XCTUnwrap(pasteboard.string(forType: .fileURL))))
        XCTAssertEqual(try Data(contentsOf: copiedURL), data)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    @MainActor
    func testCopyingWideShelfGIFResizesBothRepresentationsAndKeepsOriginal() throws {
        let data = try makeGIF(width: 2496, height: 443)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = try ShelfItem.storeGIF(data, in: folder)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(item.copy(to: pasteboard))
        let copied = try XCTUnwrap(pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")))
        let animation = try XCTUnwrap(AnimatedImage(data: copied))
        XCTAssertEqual(animation.pixelWidth, 1280)
        XCTAssertEqual(animation.pixelHeight, 227)
        XCTAssertEqual(animation.frames.count, 2)
        let fileURL = try XCTUnwrap(URL(string: XCTUnwrap(pasteboard.string(forType: .fileURL))))
        XCTAssertEqual(try Data(contentsOf: fileURL), copied)
        XCTAssertEqual(try Data(contentsOf: item.url), data)
    }

    private func makeGIF(width: Int = 4, height: Int = 3) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let frames = try [CGFloat(0), CGFloat(1)].map { red in
            context.setFillColor(red: red, green: 0, blue: 1 - red, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return AnimatedImage.Frame(image: try XCTUnwrap(context.makeImage()), duration: red == 0 ? 0.1 : 0.2)
        }
        return try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames))
    }
}
