import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ScreenRecordingGeometry: Equatable, Sendable {
    public let sourceRect: CGRect
    public let outputPixelSize: CGSize

    public init(
        screenSize: CGSize,
        selectionRect: CGRect,
        backingScale: CGFloat,
        maximumPixelDimension: CGFloat
    ) {
        let screenBounds = CGRect(origin: .zero, size: screenSize)
        let selection = selectionRect.standardized.intersection(screenBounds)
        sourceRect = CGRect(
            x: selection.minX,
            y: screenSize.height - selection.maxY,
            width: selection.width,
            height: selection.height
        )

        let rawWidth = selection.width * backingScale
        let rawHeight = selection.height * backingScale
        let longestDimension = max(rawWidth, rawHeight, 1)
        let outputScale = min(1, maximumPixelDimension / longestDimension)
        outputPixelSize = CGSize(
            width: max(1, round(rawWidth * outputScale)),
            height: max(1, round(rawHeight * outputScale))
        )
    }
}

public enum GIFFrameTimeline {
    public static func durations(
        for timestamps: [TimeInterval],
        fallbackDuration: TimeInterval
    ) -> [TimeInterval] {
        guard !timestamps.isEmpty else { return [] }
        let fallback = max(0.02, fallbackDuration)
        return timestamps.indices.map { index in
            guard index + 1 < timestamps.count else { return fallback }
            let interval = timestamps[index + 1] - timestamps[index]
            return interval.isFinite && interval > 0 ? max(0.02, interval) : fallback
        }
    }
}

public enum AnimatedGIFEncoder {
    public static func encode(frames: [AnimatedImage.Frame], loopCount: Int = 0) -> Data? {
        encode(frameCount: frames.count, loopCount: loopCount) { frames[$0] }
    }

    public static func encode(
        frameCount: Int,
        loopCount: Int = 0,
        frameProvider: (Int) -> AnimatedImage.Frame?
    ) -> Data? {
        guard frameCount > 1 else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { return nil }

        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: max(0, loopCount)]] as CFDictionary
        )
        for index in 0..<frameCount {
            guard let frame = frameProvider(index) else { return nil }
            let duration = max(0.02, frame.duration)
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: duration,
                    kCGImagePropertyGIFUnclampedDelayTime: duration
                ]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, frame.image, properties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
