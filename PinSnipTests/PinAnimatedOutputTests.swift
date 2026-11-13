import AppKit
import PinSnipCore
import XCTest

@MainActor
final class PinAnimatedOutputTests: XCTestCase {
    func testCopyingAnimatedPinPreservesAllFramesTimingAndLoopCount() async throws {
        _ = NSApplication.shared
        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: [
            AnimatedImage.Frame(image: image(red: 1), duration: 0.08),
            AnimatedImage.Frame(image: image(red: 0), duration: 0.16)
        ], loopCount: 3))
        let animation = try XCTUnwrap(AnimatedImage(data: data))
        let controller = PinWindowController(animation: animation, frame: NSRect(x: 0, y: 0, width: 4, height: 3))
        defer { controller.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let succeeded = await withCheckedContinuation { continuation in
            controller.copyOriginal(to: pasteboard) { continuation.resume(returning: $0) }
        }

        XCTAssertTrue(succeeded)
        guard case let .animatedImageData(copied) = ClipboardReader.read(from: pasteboard) else {
            return XCTFail("GIF 贴图复制后应仍为动图，不能变成首帧 PNG")
        }
        let exported = try XCTUnwrap(AnimatedImage(data: copied))
        XCTAssertEqual(exported.frames.count, 2)
        XCTAssertEqual(exported.frames[0].duration, 0.08, accuracy: 0.01)
        XCTAssertEqual(exported.frames[1].duration, 0.16, accuracy: 0.01)
        XCTAssertEqual(exported.loopCount, 3)
        XCTAssertEqual(copied, data)
        let menu = try XCTUnwrap(controller.window?.contentView?.menu)
        XCTAssertNotNil(menu.items.first { $0.title == "复制原动图" })
        XCTAssertNotNil(menu.items.first { $0.title == "保存原动图…" })
    }

    func testCopyingStillPinContinuesToOfferStaticImage() throws {
        _ = NSApplication.shared
        let controller = PinWindowController(image: try image(red: 1), frame: NSRect(x: 0, y: 0, width: 4, height: 3))
        defer { controller.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        controller.copyOriginal(to: pasteboard)

        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")))
        let menu = try XCTUnwrap(controller.window?.contentView?.menu)
        XCTAssertNotNil(menu.items.first { $0.title == "复制原图" })
        XCTAssertNotNil(menu.items.first { $0.title == "保存原图…" })
    }

    func testPinMenuShowsCurrentOpacityAndBothMirrorsAfterActions() throws {
        _ = NSApplication.shared
        let controller = PinWindowController(image: try image(red: 1), frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        defer { controller.close() }
        let menu = try XCTUnwrap(controller.window?.contentView?.menu)
        let horizontal = try XCTUnwrap(menu.item(withTitle: "水平镜像"))
        let vertical = try XCTUnwrap(menu.item(withTitle: "垂直镜像"))
        let topmost = try XCTUnwrap(menu.item(withTitle: "置顶"))
        let opacity = try XCTUnwrap(menu.items.first(where: { $0.submenu != nil }))
        let choices = try XCTUnwrap(opacity.submenu)
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(topmost.state, .on)
        XCTAssertEqual(choices.item(withTag: 100)?.state, .on)

        for item in [horizontal, vertical, topmost] + choices.items {
            let action = try XCTUnwrap(item.action)
            XCTAssertTrue(NSApp.sendAction(action, to: controller, from: item))
            controller.menuNeedsUpdate(menu)
            if item.menu === choices {
                XCTAssertEqual(opacity.title, "不透明度（\(item.tag)%）")
                XCTAssertEqual(choices.items.filter { $0.state == .on }.map(\.tag), [item.tag])
            }
        }
        XCTAssertEqual(horizontal.state, .on)
        XCTAssertEqual(vertical.state, .on)
        XCTAssertEqual(topmost.state, .off)
    }

    private func image(red: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try XCTUnwrap(context.makeImage())
    }
}
