import Foundation
import XCTest
@testable import PinSnipCore

final class ShareStyleTests: XCTestCase {
    func testBorderSizePreservesAutomaticSizingAndBoundsCustomInput() {
        XCTAssertEqual(ShareBorderSize.automatic.padding(width: 80, height: 60), 24)
        XCTAssertEqual(ShareBorderSize.automatic.padding(width: 1000, height: 600), 60)
        XCTAssertEqual(ShareBorderSize.automatic.padding(width: 3000, height: 2000), 120)
        XCTAssertEqual(ShareBorderSize(pixels: 73).padding(width: 80, height: 60), 73)
        XCTAssertEqual(ShareBorderSize(pixels: -1).pixels, 8)
        XCTAssertEqual(ShareBorderSize(pixels: Int.max).pixels, 300)
    }

    func testBorderSizePersistsAndCanReturnToAutomatic() throws {
        let suiteName = "PinSnipTests.BorderSize.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShareBorderSizeStore(defaults: defaults)
        XCTAssertEqual(store.load(), .automatic)
        store.save(ShareBorderSize(pixels: 73))
        XCTAssertEqual(ShareBorderSizeStore(defaults: defaults).load().pixels, 73)
        store.save(.automatic)
        XCTAssertEqual(ShareBorderSizeStore(defaults: defaults).load(), .automatic)
    }

    func testStylesUseProductMenuOrderAndTitles() {
        XCTAssertEqual(ShareStyle.allCases, [.paperCut, .bordered, .dusk, .original])
        XCTAssertEqual(ShareStyle.paperCut.title, "剪纸")
        XCTAssertEqual(ShareStyle.bordered.title, "边框 · 随机适配")
        XCTAssertEqual(ShareStyle.original.title, "原图")
    }

    func testStoreDefaultsToPaperCut() throws {
        let suiteName = "PinSnipTests.ShareStyle.Default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ShareStyleStore(defaults: defaults).load(), .paperCut)
    }

    func testStoreRemembersLastSelectionGlobally() throws {
        let suiteName = "PinSnipTests.ShareStyle.RoundTrip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShareStyleStore(defaults: defaults)

        store.save(.bordered)
        XCTAssertEqual(store.load(), .bordered)

        store.save(.dusk)
        XCTAssertEqual(store.load(), .dusk)

        store.save(.original)
        XCTAssertEqual(store.load(), .original)
    }
}
