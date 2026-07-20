import AppKit
import XCTest
@testable import PinSnipCore

final class ClipboardReaderTests: XCTestCase {
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
