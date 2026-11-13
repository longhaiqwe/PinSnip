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
        XCTAssertEqual(ShareStyle.allCases, [.bordered, .dusk, .ocean, .lavender, .peach, .mint, .rose, .graphite, .original])
        XCTAssertFalse(ShareStyle.allCases.contains { $0.rawValue == "paperCut" })
        XCTAssertEqual(ShareStyle.bordered.title, "渐变 · 自动配色")
        XCTAssertEqual(ShareStyle.original.title, "原图")
    }

    func testStoreDefaultsToDusk() throws {
        let suiteName = "PinSnipTests.ShareStyle.Default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ShareStyleStore(defaults: defaults).load(), .dusk)
    }

    func testStoreRemembersLastSelectionGlobally() throws {
        let suiteName = "PinSnipTests.ShareStyle.RoundTrip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShareStyleStore(defaults: defaults)

        for style in ShareStyle.allCases {
            store.save(style)
            XCTAssertEqual(ShareStyleStore(defaults: defaults).load(), style)
        }
    }
    func testRemovedPaperCutAndUnknownPreferencesFallBackToDusk() throws {
        let suiteName = "PinSnipTests.ShareStyle.Migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for value in ["paperCut", "unknown"] {
            defaults.set(value, forKey: "PinSnip.ShareStyle.v1")
            XCTAssertEqual(ShareStyleStore(defaults: defaults).load(), .dusk)
        }
    }

}
