import AppKit
import XCTest
@testable import PinSnipCore

final class ClipboardReaderTests: XCTestCase {
    func testWritesGIFAsFileWithoutStaticImageFallback() throws {
        let pasteboard = makePasteboard()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinSnipTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let gif = try makeGIF(width: 4, height: 3)

        let url = try XCTUnwrap(
            ClipboardWriter.writeGIF(
                gif,
                to: pasteboard,
                temporaryDirectory: temporaryDirectory
            )
        )

        let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(item.types, [.fileURL])
        XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertEqual(try Data(contentsOf: url), gif)
    }

    func testCopiedGIFAutomaticallyFitsLandscapeAndPortraitLimits() throws {
        for (width, height, expectedWidth, expectedHeight) in [(2496, 443, 1280, 227), (600, 2400, 270, 1080)] {
            let original = try makeGIF(width: width, height: height)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = try XCTUnwrap(ClipboardWriter.writeGIF(original, to: makePasteboard(), temporaryDirectory: folder))
            let animation = try XCTUnwrap(AnimatedImage(data: Data(contentsOf: url)))
            XCTAssertEqual(animation.pixelWidth, expectedWidth)
            XCTAssertEqual(animation.pixelHeight, expectedHeight)
            XCTAssertEqual(animation.frames.count, 2)
            XCTAssertEqual(animation.frames[0].duration, 0.1, accuracy: 0.001)
            XCTAssertEqual(animation.frames[1].duration, 0.2, accuracy: 0.001)
            XCTAssertEqual(animation.loopCount, 3)
        }
    }

    func testInvalidGIFDoesNotReplaceClipboard() {
        let pasteboard = makePasteboard()
        pasteboard.setString("keep", forType: .string)
        XCTAssertNil(ClipboardWriter.writeGIF(Data("invalid".utf8), to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
    }

    private func makeGIF(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let frames = try [CGFloat(0), CGFloat(1)].map { red in
            context.setFillColor(red: red, green: 0, blue: 1 - red, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return AnimatedImage.Frame(image: try XCTUnwrap(context.makeImage()), duration: red == 0 ? 0.1 : 0.2)
        }
        return try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames, loopCount: 3))
    }

    func testReadsGIFDataBeforeStaticImageFallback() throws {
        let pasteboard = makePasteboard()
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.setData(gif, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        pasteboard.setData(png, forType: .png)

        XCTAssertEqual(ClipboardReader.read(from: pasteboard), .animatedImageData(gif))
    }

    func testReadsPNGDataBeforeText() throws {
        let pasteboard = makePasteboard()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.setData(png, forType: .png)
        pasteboard.setString("fallback", forType: .string)

        XCTAssertEqual(ClipboardReader.read(from: pasteboard), .imageData(png))
    }

    func testReadsTIFFImageData() {
        let pasteboard = makePasteboard()
        let tiff = Data([0x49, 0x49, 0x2A, 0x00])
        pasteboard.setData(tiff, forType: .tiff)

        XCTAssertEqual(ClipboardReader.read(from: pasteboard), .imageData(tiff))
    }

    func testReadsImageFileURLBeforeText() throws {
        let pasteboard = makePasteboard()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinsnip-\(UUID().uuidString).png")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("fallback", forType: .string)

        XCTAssertEqual(ClipboardReader.read(from: pasteboard), .file(url))
    }

    func testIgnoresTextWithoutChangingTheClipboard() {
        let textPasteboard = makePasteboard()
        textPasteboard.setString("hello", forType: .string)
        let changeCount = textPasteboard.changeCount
        XCTAssertNil(ClipboardReader.read(from: textPasteboard))
        XCTAssertEqual(textPasteboard.string(forType: .string), "hello")
        XCTAssertEqual(textPasteboard.changeCount, changeCount)
    }

    func testIgnoresColorTextInsteadOfCreatingACard() {
        let colorPasteboard = makePasteboard()
        colorPasteboard.setString("#22C55E", forType: .string)
        XCTAssertNil(ClipboardReader.read(from: colorPasteboard))
    }

    func testEmptyPasteboardReturnsNil() {
        XCTAssertNil(ClipboardReader.read(from: makePasteboard()))
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PinSnipTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }
}
