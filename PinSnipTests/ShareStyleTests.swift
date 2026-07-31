import Foundation
import XCTest
@testable import PinSnipCore

final class ShareStyleTests: XCTestCase {
    func testStylesUseProductMenuOrderAndTitles() {
        XCTAssertEqual(ShareStyle.allCases, [.paperCut, .bordered, .original])
        XCTAssertEqual(ShareStyle.paperCut.title, "剪纸")
        XCTAssertEqual(ShareStyle.bordered.title, "边框")
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

        store.save(.original)
        XCTAssertEqual(store.load(), .original)
    }
}
