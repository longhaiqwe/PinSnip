import AppKit
import XCTest
import PinSnipCore

final class GIFShareSettingsInteractionTests: XCTestCase {
    @MainActor
    func testInvalidFieldIsNamedAndFocusedWithoutSavingOrClearingOtherInputs() throws {
        _ = NSApplication.shared
        let suiteName = "PinSnipTests.GIFShareSettings.UI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GIFShareSettingsStore(defaults: defaults)
        let controller = GIFShareSettingsWindowController(store: store)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let fields = views.compactMap { $0 as? NSTextField }.filter(\.isEditable)
        XCTAssertEqual(fields.count, 3)
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "保存" })

        for (index, name) in [(0, "最大宽度"), (1, "最大高度"), (2, "体积上限")] {
            fields[0].stringValue = "900"
            fields[1].stringValue = "700"
            fields[2].stringValue = "0.5"
            fields[index].stringValue = "无效"
            save.performClick(nil)

            XCTAssertEqual(store.load(), .standard)
            XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains {
                $0.stringValue.hasPrefix("\(name)请输入")
            })
            XCTAssertNotNil(fields[index].currentEditor())
            XCTAssertTrue(window.firstResponder === fields[index].currentEditor())
            XCTAssertEqual(fields[(index + 1) % 3].stringValue, ["900", "700", "0.5"][(index + 1) % 3])
            window.makeFirstResponder(nil)
        }

        fields[0].stringValue = "900"
        fields[1].stringValue = "700"
        fields[2].stringValue = "0.5"
        save.performClick(nil)
        XCTAssertEqual(store.load(), GIFShareSettings(maximumWidth: 900, maximumHeight: 700, maximumBytes: 500_000))
    }

    @MainActor
    func testCancelKeepsStoredValuesAndReopeningPreservesWindowPosition() throws {
        _ = NSApplication.shared
        let suiteName = "PinSnipTests.GIFShareSettings.Cancel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GIFShareSettingsStore(defaults: defaults)
        let controller = GIFShareSettingsWindowController(store: store)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: 163, y: 197))
        let expected = window.frame
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let fields = views.compactMap { $0 as? NSTextField }.filter(\.isEditable)
        fields[0].stringValue = "300"
        try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "取消" }).performClick(nil)
        XCTAssertEqual(store.load(), .standard)

        let reopened = GIFShareSettingsWindowController(store: store)
        defer { reopened.close() }
        XCTAssertEqual(reopened.window?.frame, expected)
        let restoredFields = descendants(of: try XCTUnwrap(reopened.window?.contentView))
            .compactMap { $0 as? NSTextField }.filter(\.isEditable)
        XCTAssertEqual(restoredFields[0].stringValue, String(GIFShareSettings.standard.maximumWidth))
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
