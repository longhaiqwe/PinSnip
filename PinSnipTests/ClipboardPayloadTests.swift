import Foundation
import XCTest
@testable import PinSnipCore

final class ClipboardPayloadTests: XCTestCase {
    func testSixDigitHexTextBecomesColorCard() {
        XCTAssertEqual(
            ClipboardPayload.classify(text: "  #0EA5E9\n"),
            .color(RGBAColor(red: 14.0 / 255, green: 165.0 / 255, blue: 233.0 / 255))
        )
    }

    func testShortHexTextBecomesExpandedColorCard() {
        XCTAssertEqual(
            ClipboardPayload.classify(text: "#f80"),
            .color(RGBAColor(red: 1, green: 136.0 / 255, blue: 0))
        )
    }

    func testEightDigitHexPreservesAlpha() {
        XCTAssertEqual(
            ClipboardPayload.classify(text: "0EA5E980"),
            .color(
                RGBAColor(
                    red: 14.0 / 255,
                    green: 165.0 / 255,
                    blue: 233.0 / 255,
                    alpha: 128.0 / 255
                )
            )
        )
    }

    func testOrdinaryTextRemainsTextWithoutTrimmingContent() {
        XCTAssertEqual(
            ClipboardPayload.classify(text: "  ship the useful thing\n"),
            .text("  ship the useful thing\n")
        )
    }

    func testMalformedHexRemainsText() {
        XCTAssertEqual(ClipboardPayload.classify(text: "#12GG34"), .text("#12GG34"))
    }
}
