import XCTest
@testable import PinSnipCore

final class PinWindowLayoutTests: XCTestCase {
    func testFirstPinIsCenteredInUsableScreenArea() {
        let visible = CGRect(x: 0, y: 90, width: 1440, height: 780)
        let frame = PinWindowLayout.initialFrame(
            imageSize: CGSize(width: 1920, height: 1080),
            visibleFrame: visible,
            cascadeIndex: 0
        )

        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.001)
        XCTAssertEqual(frame.width, 560, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, 1920.0 / 1080, accuracy: 0.001)
    }

    func testRepeatedPinsStayInsideScreensWithDifferentOriginsAndDockPositions() {
        let screens = [
            CGRect(x: 0, y: 90, width: 1440, height: 780),
            CGRect(x: -1920, y: -300, width: 1840, height: 1055),
            CGRect(x: 1440, y: 900, width: 900, height: 1300),
            CGRect(x: 80, y: 0, width: 400, height: 260)
        ]
        for visible in screens {
            for index in 0..<24 {
                for size in [CGSize(width: 4000, height: 3000), CGSize(width: 500, height: 8000)] {
                    let frame = PinWindowLayout.initialFrame(
                        imageSize: size, visibleFrame: visible, cascadeIndex: index
                    )
                    XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame), "\(frame) outside \(visible)")
                    XCTAssertEqual(frame.width / frame.height, size.width / size.height, accuracy: 0.001)
                }
            }
        }
    }

    func testCascadeIsBoundedAndStartsAgainAfterEightPins() {
        let visible = CGRect(x: 0, y: 90, width: 1440, height: 780)
        func frame(_ index: Int) -> CGRect {
            PinWindowLayout.initialFrame(
                imageSize: CGSize(width: 800, height: 600),
                visibleFrame: visible, cascadeIndex: index
            )
        }
        XCTAssertNotEqual(frame(0).origin, frame(1).origin)
        XCTAssertEqual(frame(0), frame(8))
    }

    func testSmallImagesAreNotEnlargedOrStretched() {
        let frame = PinWindowLayout.initialFrame(
            imageSize: CGSize(width: 40, height: 20),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            cascadeIndex: 0
        )
        XCTAssertEqual(frame.size, CGSize(width: 40, height: 20))
    }
}
