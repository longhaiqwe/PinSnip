import AppKit
import ImageIO
import XCTest
@testable import PinSnipCore

final class GIFShareSettingsTests: XCTestCase {
    func testSettingsPersistCustomValuesAndZeroLimits() throws {
        let suite = "PinSnipTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GIFShareSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .standard)
        let custom = GIFShareSettings(maximumWidth: 900, maximumHeight: 700, maximumBytes: 500_000)
        store.save(custom)
        XCTAssertEqual(GIFShareSettingsStore(defaults: defaults).load(), custom)
        store.save(.original)
        XCTAssertEqual(store.load(), .original)
        defaults.set(["maximumWidth": "bad"], forKey: "PinSnip.GIFShareSettings.v1")
        XCTAssertEqual(store.load(), .standard)
    }

    func testOriginalKeepsExactBytesAndInvalidGIFThrows() throws {
        let data = try makeNoiseGIF()
        XCTAssertEqual(try GIFShareEncoder.encode(data, settings: .original), data)
        XCTAssertThrowsError(try GIFShareEncoder.encode(Data("bad".utf8), settings: .original))
    }

    func testByteLimitAdaptsSizeWithoutTruncatingOrLosingLoopCount() throws {
        let data = try makeNoiseGIF()
        XCTAssertGreaterThan(data.count, 100_000)
        let result = try GIFShareEncoder.encode(data, settings: GIFShareSettings(
            maximumWidth: 640, maximumHeight: 640, maximumBytes: 100_000
        ))
        XCTAssertLessThanOrEqual(result.count, 100_000)
        let decoded = try XCTUnwrap(AnimatedImage(data: result))
        XCTAssertEqual(decoded.loopCount, 4)
        XCTAssertEqual(decoded.frames.reduce(0) { $0 + $1.duration }, 0.4, accuracy: 0.001)
        XCTAssertGreaterThan(decoded.frames.count, 1)
        XCTAssertLessThan(decoded.pixelWidth, 512)
    }

    func testStandardReducesExcessFramesAndPreservesFullDuration() throws {
        let image = try noiseImage(width: 32, height: 24)
        let frames = (0..<354).map { index in
            AnimatedImage.Frame(image: image, duration: index % 2 == 0 ? 0.04 : 0.06)
        }
        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames, loopCount: 2))
        let output = try GIFShareEncoder.encode(data, settings: .standard)
        let animation = try XCTUnwrap(AnimatedImage(data: output))
        XCTAssertLessThanOrEqual(animation.frames.count, 350)
        XCTAssertEqual(animation.frames.reduce(0) { $0 + $1.duration }, 17.7, accuracy: 0.001)
        XCTAssertEqual(animation.loopCount, 2)
    }

    func testFrameReductionRetainsTheFinalLongHold() throws {
        let image = try noiseImage(width: 160, height: 160)
        let frames = (0..<354).map { index in
            AnimatedImage.Frame(image: image, duration: index == 353 ? 600 : 0.01)
        }
        let data = try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames))
        let result = try GIFShareEncoder.encode(data, settings: .standard)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let final = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetCount(source) - 1, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(final[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(try XCTUnwrap(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double), 600, accuracy: 0.001)
    }

    private func makeNoiseGIF() throws -> Data {
        let frames = try (0..<4).map { _ in
            AnimatedImage.Frame(image: try noiseImage(width: 512, height: 256), duration: 0.1)
        }
        return try XCTUnwrap(AnimatedGIFEncoder.encode(frames: frames, loopCount: 4))
    }

    private func noiseImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var seed: UInt64 = 1234567
        for index in 0..<(width * height) {
            seed = seed &* 6364136223846793005 &+ 1
            pixels[index * 4] = UInt8(truncatingIfNeeded: seed >> 32)
            pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: seed >> 40)
            pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: seed >> 48)
            pixels[index * 4 + 3] = 255
        }
        return try XCTUnwrap(context.makeImage())
    }
}
