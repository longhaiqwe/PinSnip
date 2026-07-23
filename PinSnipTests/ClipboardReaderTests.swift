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
        let gif = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])

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

    func testClassifiesTextAndColor() throws {
        let textPasteboard = makePasteboard()
        textPasteboard.setString("hello", forType: .string)
        XCTAssertEqual(ClipboardReader.read(from: textPasteboard), .text("hello"))

        let colorPasteboard = makePasteboard()
        colorPasteboard.setString("#22C55E", forType: .string)
        XCTAssertEqual(
            ClipboardReader.read(from: colorPasteboard),
            .color(RGBAColor(red: 34.0 / 255, green: 197.0 / 255, blue: 94.0 / 255))
        )
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
