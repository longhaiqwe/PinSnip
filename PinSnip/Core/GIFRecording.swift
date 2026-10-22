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
        fallbackDuration: TimeInterval,
        endTimestamp: TimeInterval? = nil
    ) -> [TimeInterval] {
        guard !timestamps.isEmpty else { return [] }
        let fallback = max(0.02, fallbackDuration)
        return timestamps.indices.map { index in
            let next = index + 1 < timestamps.count ? timestamps[index + 1] : endTimestamp
            guard let next else { return fallback }
            let interval = next - timestamps[index]
            return interval.isFinite && interval > 0 ? max(0.02, interval) : fallback
        }
    }
}

public enum GIFRecordingOutputAction: Equatable, Sendable {
    case copy
    case save
}

public struct GIFRecordingCompletionPlan: Equatable, Sendable {
    public let copiesToClipboard: Bool
    public let presentsSavePanel: Bool

    public init(action: GIFRecordingOutputAction) {
        switch action {
        case .copy:
            self.init(copiesToClipboard: true, presentsSavePanel: false)
        case .save:
            self.init(copiesToClipboard: false, presentsSavePanel: true)
        }
    }

    public init(copiesToClipboard: Bool, presentsSavePanel: Bool) {
        self.copiesToClipboard = copiesToClipboard
        self.presentsSavePanel = presentsSavePanel
    }
}

public enum AnimatedGIFEncoder {
    public static func encode(frames: [AnimatedImage.Frame], loopCount: Int = 0) -> Data? {
        encode(frameCount: frames.count, loopCount: loopCount) { frames[$0] }
    }

    public static func encodeRecording(
        frames: [AnimatedImage.Frame],
        loopCount: Int = 0,
        style: ShareStyle = .paperCut,
        borderSize: ShareBorderSize = .automatic
    ) -> Data? {
        encodeRecording(frameCount: frames.count, loopCount: loopCount, style: style, borderSize: borderSize) { frames[$0] }
    }

    public static func encodeRecording(
        frameCount: Int,
        loopCount: Int = 0,
        style: ShareStyle = .paperCut,
        borderSize: ShareBorderSize = .automatic,
        frameProvider: (Int) -> AnimatedImage.Frame?
    ) -> Data? {
        encodeStyled(
            frameCount: frameCount,
            loopCount: loopCount,
            style: style,
            borderSize: borderSize,
            frameProvider: frameProvider
        )
    }

    public static func encodeShareCard(
        frames: [AnimatedImage.Frame],
        loopCount: Int = 0
    ) -> Data? {
        encodeShareCard(frameCount: frames.count, loopCount: loopCount) { frames[$0] }
    }

    public static func encodeShareCard(
        frameCount: Int,
        loopCount: Int = 0,
        frameProvider: (Int) -> AnimatedImage.Frame?
    ) -> Data? {
        encodeStyled(
            frameCount: frameCount,
            loopCount: loopCount,
            style: .paperCut,
            borderSize: .automatic,
            frameProvider: frameProvider
        )
    }

    private static func encodeStyled(
        frameCount: Int,
        loopCount: Int,
        style: ShareStyle,
        borderSize: ShareBorderSize,
        frameProvider: (Int) -> AnimatedImage.Frame?
    ) -> Data? {
        guard frameCount > 1,
              let firstFrame = frameProvider(0),
              let template = ShareCardRenderer.Template(
                styleSource: firstFrame.image,
                style: style,
                borderSize: borderSize
              )
        else { return nil }

        return encode(frameCount: frameCount, loopCount: loopCount) { index in
            let frame: AnimatedImage.Frame?
            if index == 0 {
                frame = firstFrame
            } else {
                frame = frameProvider(index)
            }
            guard let frame,
                  let image = template.render(baseImage: frame.image)
            else { return nil }
            return AnimatedImage.Frame(image: image, duration: frame.duration)
        }
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
        var elapsed: TimeInterval = 0
        var encodedCentiseconds = 0
        for index in 0..<frameCount {
            let added = autoreleasepool { () -> Bool in
                guard let frame = frameProvider(index) else { return false }
                // GIF stores hundredths of a second. Round the cumulative timeline
                // so fractional capture intervals do not speed up a long recording.
                elapsed += frame.duration.isFinite ? max(0.02, frame.duration) : 0.1
                let nextCentiseconds = max(encodedCentiseconds + 2, Int((elapsed * 100).rounded()))
                let duration = Double(nextCentiseconds - encodedCentiseconds) / 100
                encodedCentiseconds = nextCentiseconds
                let properties = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: duration,
                        kCGImagePropertyGIFUnclampedDelayTime: duration
                    ]
                ] as CFDictionary
                CGImageDestinationAddImage(destination, frame.image, properties)
                return true
            }
            guard added else { return nil }
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
