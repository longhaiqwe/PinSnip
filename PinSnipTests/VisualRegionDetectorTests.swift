import CoreGraphics
import XCTest
@testable import PinSnipCore

final class VisualRegionDetectorTests: XCTestCase {
    func testDetectsHighContrastModalInsteadOfNestedCard() throws {
        let image = try XCTUnwrap(makeModalScreenshot())

        let candidates = VisualRegionDetector().candidates(
            in: image,
            viewSize: CGSize(width: 800, height: 600)
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.kind, .visualRegion)
        XCTAssertEqual(candidate.frame.minX, 200, accuracy: 6)
        XCTAssertEqual(candidate.frame.minY, 120, accuracy: 6)
        XCTAssertEqual(candidate.frame.width, 400, accuracy: 12)
        XCTAssertEqual(candidate.frame.height, 360, accuracy: 12)
    }

    func testVisualRegionWinsOverContainingApplicationWindow() {
        let applicationWindow = WindowCandidate(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            zOrder: 0
        )
        let modal = WindowCandidate(
            id: 2,
            frame: CGRect(x: 200, y: 120, width: 400, height: 360),
            zOrder: 0,
            kind: .visualRegion
        )

        let candidate = WindowCandidate.best(
            at: CGPoint(x: 400, y: 300),
            in: [applicationWindow, modal]
        )

        XCTAssertEqual(candidate, modal)
    }

    private func makeModalScreenshot() -> CGImage? {
        let width = 800
        let height = 600
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(
            CGColor(red: 0.28, green: 0.29, blue: 0.31, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(
            CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        )
        context.fill(CGRect(x: 200, y: 120, width: 400, height: 360))

        context.setFillColor(
            CGColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
        )
        context.fill(CGRect(x: 240, y: 300, width: 320, height: 90))

        return context.makeImage()
    }
}
